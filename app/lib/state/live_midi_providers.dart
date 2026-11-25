import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/midi/pad_leds.dart';

import '../models/live_grid.dart';
import '../models/midi_mapping.dart';
import 'live_providers.dart';
import 'midi_control_providers.dart';
import 'provider_reader.dart';

/// Something on the Live Grid a pad can press: a clip, a row's launch
/// button, GO, Stop all or one lane's stop.
class LiveMidiTarget {
  final MidiActionKind action;

  /// The lane, for a clip or a lane stop.
  final String? laneId;

  /// The row, for a clip or a row launch — its stable id, not its index.
  final String? rowId;

  const LiveMidiTarget.clip(String this.laneId, String this.rowId) : action = MidiActionKind.liveClip;
  const LiveMidiTarget.row(String this.rowId) : action = MidiActionKind.liveRow, laneId = null;
  const LiveMidiTarget.go() : action = MidiActionKind.liveGo, laneId = null, rowId = null;
  const LiveMidiTarget.stopAll() : action = MidiActionKind.liveStopAll, laneId = null, rowId = null;
  const LiveMidiTarget.stopLane(String this.laneId) : action = MidiActionKind.liveStopLane, rowId = null;

  bool matches(MidiMapping m) => m.action == action && m.param == laneId && m.targetId == rowId;

  MidiMapping mappingFor(MidiTrigger trigger, {String id = ''}) =>
      MidiMapping(id: id, trigger: trigger, action: action, param: laneId, targetId: rowId);

  @override
  bool operator ==(Object other) =>
      other is LiveMidiTarget && other.action == action && other.laneId == laneId && other.rowId == rowId;

  @override
  int get hashCode => Object.hash(action, laneId, rowId);
}

/// On while the Grid's MIDI button is lit: a tap picks what the next pad
/// press is bound to instead of playing.
final liveMidiLearnProvider = StateProvider<bool>((ref) => false);

/// The mapping bound to [target], if any.
MidiMapping? liveMidiMappingFor(List<MidiMapping> mappings, LiveMidiTarget target) {
  for (final m in mappings) {
    if (target.matches(m)) return m;
  }
  return null;
}

/// Binds [trigger] to [target]. The target keeps one pad (a new press
/// replaces its old one), and the pad leaves whatever it did before.
MidiMapping assignLiveMidi(ReadProvider read, LiveMidiTarget target, MidiTrigger trigger) {
  final existing = liveMidiMappingFor(read(midiMappingsProvider), target);
  return read(midiMappingsProvider.notifier).save(target.mappingFor(trigger, id: existing?.id ?? ''));
}

/// Unbinds [target]; false when it had no pad.
bool clearLiveMidi(ReadProvider read, LiveMidiTarget target) {
  final existing = liveMidiMappingFor(read(midiMappingsProvider), target);
  if (existing == null) return false;
  read(midiMappingsProvider.notifier).remove(existing.id);
  return true;
}

/// "C1", "CC 20", "PC 3" — what fits on a badge on a clip.
String shortTriggerLabel(MidiTrigger t) => switch (t.kind) {
  MidiTriggerKind.note => MidiTrigger.noteName(t.number),
  MidiTriggerKind.cc => 'CC ${t.number}',
  MidiTriggerKind.program => 'PC ${t.number + 1}',
};

/// The lanes a pad block fills, left to right: those with a clip in the
/// first [rows] rows (an empty Show lane would waste a column of pads).
List<LiveLane> padLanes(LiveGrid grid, {int rows = 4}) => [
  for (final lane in grid.lanes)
    if (Iterable<int>.generate(rows.clamp(0, grid.rows.length)).any((r) => grid.clipAt(lane.id, r) != null)) lane,
];

/// A 4×4 pad block over the top-left of the Grid: pad (r, c) presses
/// lane c's clip in row r. Learned from two presses — the top-left pad
/// and the one under it — so it fits a controller numbering its pads
/// either way; along a row, the numbers go up by one.
List<(LiveMidiTarget, MidiTrigger)> padBlock(
  LiveGrid grid, {
  required MidiTrigger topLeft,
  required MidiTrigger below,
  int size = 4,
}) {
  final step = below.number - topLeft.number;
  final lanes = padLanes(grid, rows: size).take(size).toList();
  final out = <(LiveMidiTarget, MidiTrigger)>[];
  for (var r = 0; r < size && r < grid.rows.length; r++) {
    for (var c = 0; c < lanes.length; c++) {
      if (grid.clipAt(lanes[c].id, r) == null) continue;
      final number = topLeft.number + r * step + c;
      if (number < 0 || number > 127) continue;
      out.add((
        LiveMidiTarget.clip(lanes[c].id, grid.rowIds[r]),
        MidiTrigger(kind: topLeft.kind, channel: topLeft.channel, number: number),
      ));
    }
  }
  return out;
}

// --- Pad LEDs ------------------------------------------------------------------

const prefPadLeds = 'midiControl.leds';

/// Whether mapped pads show the Grid's state. Off until the LED test shows
/// the controller lights up from plain MIDI. A tablet setting.
final padLedsEnabledProvider = StateNotifierProvider<PadLedsEnabledNotifier, bool>((ref) => PadLedsEnabledNotifier());

class PadLedsEnabledNotifier extends StateNotifier<bool> {
  PadLedsEnabledNotifier() : super(false) {
    _load();
  }

  bool _touched = false;

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (_touched || !mounted) return;
      state = sp.getBool(prefPadLeds) ?? false;
    } catch (_) {}
  }

  void set(bool value) {
    _touched = true;
    state = value;
    unawaited(() async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setBool(prefPadLeds, value);
      } catch (_) {}
    }());
  }
}

/// Keeps the mapped pads' LEDs in step with the Grid. Created at startup
/// (see `watchMidiControl`), so the pads light without opening the Grid.
final padLedsProvider = Provider<PadLeds>((ref) {
  final service = ref.watch(midiControlProvider).service;
  final sender = PadLedSender(service.send);
  void refresh() {
    if (!ref.read(padLedsEnabledProvider)) {
      sender.update(const {});
      return;
    }
    sender.update(
      liveLedState(
        grid: ref.read(liveGridProvider),
        status: ref.read(liveStatusProvider),
        mappings: ref.read(midiMappingsProvider),
      ),
    );
  }

  ref.listen(liveStatusProvider, (_, _) => refresh());
  ref.listen(liveGridProvider, (_, _) => refresh());
  ref.listen(midiMappingsProvider, (_, _) => refresh());
  ref.listen(padLedsEnabledProvider, (_, _) => refresh());
  // A controller plugged in (or back from a Bluetooth drop) shows nothing:
  // send it everything again.
  var devices = service.connectedDevices.length;
  void onDevices() {
    final now = service.connectedDevices.length;
    if (now > devices) sender.forget();
    devices = now;
    refresh();
  }

  service.revision.addListener(onDevices);
  ref.onDispose(() {
    service.revision.removeListener(onDevices);
    sender.dispose();
  });
  refresh();
  return PadLeds(sender, refresh);
});

/// The running LED feedback: [resend] puts every pad's colour back after
/// something else (the LED test) painted over them.
class PadLeds {
  final PadLedSender sender;
  final void Function() _refresh;
  PadLeds(this.sender, this._refresh);

  void resend() {
    sender.forget();
    _refresh();
  }
}

/// The pads the LED test lights: every note pad mapped, or — with none
/// mapped yet — the SMC-PAD's usual pad notes (channel 10, 36–51, and the
/// clip-launch preset's channel 1, 1–16).
List<MidiTrigger> ledTestPads(List<MidiMapping> mappings) {
  final mapped = {
    for (final m in mappings)
      if (m.trigger.kind == MidiTriggerKind.note) m.trigger,
  };
  if (mapped.isNotEmpty) return mapped.toList();
  return [
    for (var n = 36; n < 52; n++) MidiTrigger(kind: MidiTriggerKind.note, channel: 9, number: n),
    for (var n = 1; n <= 16; n++) MidiTrigger(kind: MidiTriggerKind.note, channel: 0, number: n),
  ];
}

/// Runs the pads through a few colours, then hands them back to the Grid.
/// Returns once done.
Future<void> runPadLedTest(ReadProvider read, {Duration step = const Duration(milliseconds: 800)}) async {
  final service = read(midiControlProvider).service;
  final pads = ledTestPads(read(midiMappingsProvider));
  final test = PadLedSender(service.send);
  for (final colour in PadLed.testSequence) {
    test.update({for (final p in pads) p: colour});
    await Future<void>.delayed(step);
  }
  test.dispose();
  read(padLedsProvider).resend();
}

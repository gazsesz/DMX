import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_grid.dart';
import '../models/midi_mapping.dart';
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

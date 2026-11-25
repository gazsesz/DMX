import 'dart:async';
import 'dart:collection';

import '../../models/live_grid.dart';
import '../../models/midi_mapping.dart';
import '../live/live_engine.dart';

/// Pad colours, as velocities of a Note On sent back to the pad. Measured on
/// the M-VAVE SMC-PAD, where the velocity picks a colour from a fixed
/// palette rather than a brightness; other controllers with a velocity
/// palette (most clip-launch pads) read them as some colour too.
abstract final class PadLed {
  static const off = 0;
  static const green = 5;

  /// Light blue: a pad that has a clip, ready to go.
  static const ready = 7;
  static const redPink = 14;
  static const orange = 15;
  static const blue = 21;
  static const white = 40;

  /// The LED test runs through these.
  static const testSequence = [green, orange, blue, white, redPink, off];
}

/// What each mapped pad should show for the Grid as it stands: running
/// green, NEXT orange, a clip ready light blue, nothing dark. GO lights
/// orange while something waits for it; the stops light while there is
/// something to stop. Only note pads — a Note On can't light a CC button.
Map<MidiTrigger, int> liveLedState({
  required LiveGrid grid,
  required LiveStatus status,
  required List<MidiMapping> mappings,
}) {
  final out = <MidiTrigger, int>{};
  for (final m in mappings) {
    if (m.trigger.kind != MidiTriggerKind.note) continue;
    final int? colour = switch (m.action) {
      MidiActionKind.liveClip => () {
        final row = m.targetId == null ? null : grid.rowOf(m.targetId!);
        final lane = m.param;
        if (row == null || lane == null || grid.clipAt(lane, row) == null) return PadLed.off;
        if (status.queued[lane] == row) return PadLed.orange;
        if (status.running[lane] == row) return PadLed.green;
        return PadLed.ready;
      }(),
      MidiActionKind.liveRow => () {
        final row = m.targetId == null ? null : grid.rowOf(m.targetId!);
        if (row == null) return PadLed.off;
        if (status.running.values.contains(row)) return PadLed.green;
        if (status.queued.values.contains(row)) return PadLed.orange;
        return PadLed.ready;
      }(),
      MidiActionKind.liveGo => status.queued.isEmpty ? PadLed.off : PadLed.orange,
      MidiActionKind.liveStopAll => status.running.isEmpty ? PadLed.off : PadLed.redPink,
      MidiActionKind.liveStopLane => status.running.containsKey(m.param) ? PadLed.redPink : PadLed.off,
      _ => null,
    };
    if (colour != null) out[m.trigger] = colour;
  }
  return out;
}

/// Sends pad colours as they change, paced: a controller fed dozens of
/// Note Ons back to back drops some (the SMC-PAD's input buffer overruns).
class PadLedSender {
  final void Function(List<int> bytes) send;

  /// Gap between two messages.
  final Duration pace;

  PadLedSender(this.send, {this.pace = const Duration(milliseconds: 8)});

  final Map<MidiTrigger, int> _shown = {};
  final LinkedHashMap<MidiTrigger, int> _pending = LinkedHashMap();
  Timer? _timer;

  /// What the pads show (or will, once the queue is out).
  Map<MidiTrigger, int> get shown => {..._shown, ..._pending};

  /// Brings the pads to [wanted]; pads no longer in it go dark.
  void update(Map<MidiTrigger, int> wanted) {
    final now = shown;
    for (final entry in now.entries) {
      if (!wanted.containsKey(entry.key) && entry.value != PadLed.off) _queue(entry.key, PadLed.off);
    }
    for (final entry in wanted.entries) {
      if (now[entry.key] != entry.value) _queue(entry.key, entry.value);
    }
  }

  /// A controller (re)connected and shows nothing we sent: the next
  /// [update] sends everything again.
  void forget() {
    _shown.clear();
    _pending.clear();
  }

  void _queue(MidiTrigger trigger, int velocity) {
    _pending.remove(trigger);
    _pending[trigger] = velocity;
    _timer ??= Timer.periodic(pace, (_) => _pump());
  }

  void _pump() {
    if (_pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final trigger = _pending.keys.first;
    final velocity = _pending.remove(trigger)!;
    _shown[trigger] = velocity;
    send([0x90 | (trigger.channel & 0x0F), trigger.number & 0x7F, velocity & 0x7F]);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

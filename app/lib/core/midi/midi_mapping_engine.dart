import '../../models/midi_mapping.dart';
import 'midi_input_message.dart';

/// A mapping that an incoming message set off, with the control's position
/// (0..1) for continuous actions.
class MidiFiring {
  final MidiMapping mapping;

  /// 0..1 — the fader/knob position for a continuous action, 1 for a press.
  final double value;

  const MidiFiring(this.mapping, this.value);
}

/// Decides which mappings an incoming message fires. Pure logic, no I/O, so
/// it can be tested without a device.
///
/// Buttons:
/// - a Note fires on press (Note On with velocity > 0); the release does
///   nothing, so a pad toggles rather than acting like a flash button;
/// - a CC fires when it crosses from below 64 to 64 or above — buttons that
///   send CC 127 on press and 0 on release fire once per press, and a fader
///   mapped by mistake to a button fires once on the way up instead of on
///   every step;
/// - a Program Change fires every time.
///
/// Continuous actions (faders/knobs) follow the CC value, 0–127 → 0..1. A
/// note bound to one jumps to full on press and back to zero on release.
class MidiMappingEngine {
  final Map<MidiTrigger, int> _lastCc = {};

  List<MidiFiring> handle(MidiInputMessage message, List<MidiMapping> mappings) {
    final trigger = message.trigger;
    final matching = [for (final m in mappings) if (m.trigger == trigger) m];

    int? previousCc;
    if (message.kind == MidiTriggerKind.cc) {
      previousCc = _lastCc[trigger];
      _lastCc[trigger] = message.value;
    }
    if (matching.isEmpty) return const [];

    final out = <MidiFiring>[];
    for (final mapping in matching) {
      if (mapping.action.isContinuous) {
        switch (message.kind) {
          case MidiTriggerKind.cc:
            out.add(MidiFiring(mapping, message.value / 127));
          case MidiTriggerKind.note:
            out.add(MidiFiring(mapping, message.noteOff ? 0 : 1));
          case MidiTriggerKind.program:
            break;
        }
        continue;
      }
      final pressed = switch (message.kind) {
        MidiTriggerKind.note => !message.noteOff,
        MidiTriggerKind.cc => message.value >= 64 && (previousCc == null || previousCc < 64),
        MidiTriggerKind.program => true,
      };
      if (pressed) out.add(MidiFiring(mapping, 1));
    }
    return out;
  }

  void reset() => _lastCc.clear();
}

/// Tap tempo: the BPM implied by the last few taps, or null until there are
/// two taps close enough together to mean anything.
class TapTempo {
  /// A gap longer than this starts a new tap sequence.
  static const maxGap = Duration(seconds: 2);
  static const _keep = 4;

  final List<DateTime> _taps = [];

  double? tap(DateTime now) {
    if (_taps.isNotEmpty && now.difference(_taps.last) > maxGap) _taps.clear();
    _taps.add(now);
    if (_taps.length > _keep + 1) _taps.removeAt(0);
    if (_taps.length < 2) return null;
    final spanMs = _taps.last.difference(_taps.first).inMicroseconds / 1000;
    if (spanMs <= 0) return null;
    return 60000 * (_taps.length - 1) / spanMs;
  }
}

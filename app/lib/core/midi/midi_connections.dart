import 'package:flutter_midi_command/flutter_midi_command.dart';

/// Who holds a MIDI device open. The beat source (MIDI clock) and the
/// controller input can use the same device at once — a DAW sending both
/// clock and notes, say — so neither may close the port while the other
/// still needs it. The native connection is opened by the first holder and
/// closed when the last one lets go.
class MidiConnections {
  MidiConnections._();

  static final Map<String, Set<String>> _holders = {};

  /// Whether anyone other than [owner] holds [deviceId].
  static bool heldByOthers(String deviceId, String owner) =>
      (_holders[deviceId] ?? const {}).any((h) => h != owner);

  /// Connects [device] for [owner] (only opening the native port if nobody
  /// has it yet). Throws whatever the platform throws.
  static Future<void> acquire(MidiCommand midi, MidiDevice device, String owner) async {
    final holders = _holders.putIfAbsent(device.id, () => {});
    final alreadyOpen = holders.isNotEmpty && device.connected;
    holders.add(owner);
    if (alreadyOpen) return;
    try {
      await midi.connectToDevice(device);
    } catch (_) {
      holders.remove(owner);
      if (holders.isEmpty) _holders.remove(device.id);
      rethrow;
    }
  }

  /// Lets go of [device] for [owner], closing it if nobody else holds it.
  static void release(MidiCommand midi, MidiDevice device, String owner) {
    final holders = _holders[device.id];
    holders?.remove(owner);
    if (holders != null && holders.isNotEmpty) return;
    _holders.remove(device.id);
    try {
      midi.disconnectDevice(device);
    } catch (_) {
      // Already gone (unplugged) — nothing to close.
    }
  }

  static void resetForTest() => _holders.clear();
}

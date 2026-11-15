import '../../models/midi_mapping.dart';

/// One channel message from a controller, decoded from raw MIDI bytes —
/// only the kinds a mapping can bind to (Note On/Off, Control Change,
/// Program Change). Clock and other system bytes are skipped.
class MidiInputMessage {
  final MidiTriggerKind kind;
  final int channel;
  final int number;

  /// Velocity for a note (0 = released), the CC value, 0 for a program change.
  final int value;

  /// A Note Off, or a Note On with velocity 0 (the usual "released").
  final bool noteOff;

  const MidiInputMessage({
    required this.kind,
    required this.channel,
    required this.number,
    required this.value,
    this.noteOff = false,
  });

  MidiTrigger get trigger => MidiTrigger(kind: kind, channel: channel, number: number);

  @override
  String toString() => '${trigger.label} = $value${noteOff ? ' (off)' : ''}';
}

/// Splits one incoming packet into channel messages.
///
/// A packet can hold several messages (BLE MIDI and some USB devices batch
/// them) and may use running status (the status byte left out when it
/// repeats). Real-time bytes (clock, start/stop) can sit anywhere, even in
/// the middle of a message, and are skipped without breaking it. SysEx is
/// skipped whole.
///
/// [runningStatus] carries the last status byte between packets of the same
/// device — pass the same [MidiRunningStatus] for every packet from it.
List<MidiInputMessage> parseMidiPacket(List<int> data, [MidiRunningStatus? runningStatus]) {
  final state = runningStatus ?? MidiRunningStatus();
  final out = <MidiInputMessage>[];
  final pending = <int>[];
  var inSysex = false;

  void emit(int status, List<int> d) {
    final type = status & 0xF0;
    final channel = status & 0x0F;
    switch (type) {
      case 0x80:
        out.add(MidiInputMessage(kind: MidiTriggerKind.note, channel: channel, number: d[0], value: 0, noteOff: true));
      case 0x90:
        out.add(MidiInputMessage(
          kind: MidiTriggerKind.note,
          channel: channel,
          number: d[0],
          value: d[1],
          noteOff: d[1] == 0,
        ));
      case 0xB0:
        out.add(MidiInputMessage(kind: MidiTriggerKind.cc, channel: channel, number: d[0], value: d[1]));
      case 0xC0:
        out.add(MidiInputMessage(kind: MidiTriggerKind.program, channel: channel, number: d[0], value: 0));
      default:
        // Aftertouch, pitch bend: decoded only to stay in step, not mapped.
        break;
    }
  }

  for (final byte in data) {
    if (byte >= 0xF8) continue; // real-time: clock, start, stop, active sensing…
    if (byte == 0xF0) {
      inSysex = true;
      continue;
    }
    if (inSysex) {
      if (byte == 0xF7) {
        inSysex = false;
        continue;
      }
      if (byte < 0x80) continue;
      // Any other status byte ends a sysex the sender never closed.
      inSysex = false;
    }
    if (byte >= 0x80) {
      pending.clear();
      // System common (0xF1–0xF7) cancels running status.
      state.status = byte < 0xF0 ? byte : null;
      continue;
    }
    final status = state.status;
    if (status == null) continue;
    pending.add(byte);
    if (pending.length == _dataBytesFor(status)) {
      emit(status, pending);
      pending.clear();
    }
  }
  return out;
}

int _dataBytesFor(int status) => switch (status & 0xF0) {
  0xC0 || 0xD0 => 1,
  _ => 2,
};

/// The running status of one input, kept across its packets.
class MidiRunningStatus {
  int? status;
}

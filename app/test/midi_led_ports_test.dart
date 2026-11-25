import 'dart:typed_data';

import 'package:dmx_controller/core/midi/midi_control_service.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMidi extends Fake implements MidiCommand {
  final List<MidiDevice> list;
  final connected = <String>[];
  final sent = <String, List<List<int>>>{};

  _FakeMidi(this.list);

  @override
  Future<List<MidiDevice>?> get devices async => list;

  @override
  Future<void> connectToDevice(MidiDevice device, {Duration? awaitConnectionTimeout}) async =>
      connected.add(device.id);

  @override
  void disconnectDevice(MidiDevice device) => connected.remove(device.id);

  @override
  void sendData(Uint8List data, {String? deviceId, int? timestamp}) =>
      sent.putIfAbsent(deviceId!, () => []).add(data.toList());

  @override
  Stream<MidiPacket>? get onMidiPacketReceived => null;

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => null;
}

MidiDevice _port(String base, int n) => MidiDevice('$base#port=$n', 'SMC-PAD [${n + 1}]', MidiDeviceType.serial, false);

void main() {
  test('LED colours go to every port of the picked USB controller, presses only from the picked one', () async {
    final pad = [_port('usb:7', 0), _port('usb:7', 1), _port('usb:7', 2)];
    final other = MidiDevice('usb:9#port=0', 'Keys', MidiDeviceType.serial, false);
    final midi = _FakeMidi([...pad, other]);
    final service = MidiControlService(midi: midi);

    expect(await service.connect(pad[0]), isTrue);
    expect(service.connectedDevices.map((d) => d.id), ['usb:7#port=0']);
    expect(service.ledPortCount, 2);

    service.send([0x90, 36, 5]);
    expect(midi.sent.keys.toSet(), {'usb:7#port=0', 'usb:7#port=1', 'usb:7#port=2'});

    service.disconnect(pad[0]);
    await Future<void>.delayed(Duration.zero);
    expect(service.ledPortCount, 0);
  });

  test('physicalId strips the port suffix', () {
    expect(MidiControlService.physicalId('usb:7#port=2'), 'usb:7');
    expect(MidiControlService.physicalId('ble:AA'), 'ble:AA');
  });
}

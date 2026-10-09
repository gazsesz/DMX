import 'dart:convert';
import 'dart:typed_data';

import 'package:dmx_controller/core/audio/osc_beat_source.dart';
import 'package:dmx_controller/core/audio/osc_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an OSC string: null-terminated, padded to 4 bytes.
List<int> _str(String s) {
  final bytes = [...utf8.encode(s), 0];
  while (bytes.length % 4 != 0) {
    bytes.add(0);
  }
  return bytes;
}

List<int> _f32(double v) => (ByteData(4)..setFloat32(0, v)).buffer.asUint8List();
List<int> _i32(int v) => (ByteData(4)..setInt32(0, v)).buffer.asUint8List();

/// An OSC message with one float argument, the way rkbx_link (rosc) sends it.
Uint8List _floatMsg(String address, double value) =>
    Uint8List.fromList([..._str(address), ..._str(',f'), ..._f32(value)]);

Uint8List _bundle(List<Uint8List> elements) => Uint8List.fromList([
  ..._str('#bundle'),
  ...List.filled(8, 0),
  for (final e in elements) ...[..._i32(e.length), ...e],
]);

void main() {
  group('decodeOscPacket', () {
    test('decodes a float message', () {
      final messages = decodeOscPacket(_floatMsg('/master/bpm/current', 127.5));
      expect(messages, hasLength(1));
      expect(messages.single.address, '/master/bpm/current');
      expect(messages.single.firstNumber, closeTo(127.5, 1e-6));
    });

    test('decodes string and int arguments', () {
      final packet = Uint8List.fromList([..._str('/master/track/title'), ..._str(',si'), ..._str('Song'), ..._i32(7)]);
      final message = decodeOscPacket(packet).single;
      expect(message.args, ['Song', 7]);
    });

    test('decodes every message in a bundle', () {
      final messages = decodeOscPacket(_bundle([
        _floatMsg('/master/beat/trigger/1', 1),
        _floatMsg('/master/bpm/current', 128),
      ]));
      expect(messages.map((m) => m.address), ['/master/beat/trigger/1', '/master/bpm/current']);
    });

    test('truncated or garbage input returns nothing instead of throwing', () {
      final full = _floatMsg('/master/bpm/current', 128);
      expect(decodeOscPacket(Uint8List.sublistView(full, 0, 6)), isEmpty);
      expect(decodeOscPacket(Uint8List.fromList([1, 2, 3, 4, 5])), isEmpty);
      expect(decodeOscPacket(Uint8List(0)), isEmpty);
    });
  });

  group('OscBeatSource', () {
    test('a beat trigger fires a beat; a release (0.0) does not', () async {
      final source = OscBeatSource();
      final beats = <DateTime>[];
      final sub = source.beatEvents.listen(beats.add);
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 1));
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 0));
      await Future<void>.delayed(Duration.zero);
      expect(beats, hasLength(1));
      await sub.cancel();
      source.dispose();
    });

    test('other rkbx_link messages count as activity but not beats', () async {
      final source = OscBeatSource();
      final beats = <DateTime>[];
      final activity = <DateTime>[];
      final subs = [source.beatEvents.listen(beats.add), source.activity.listen(activity.add)];
      source.handlePacket(_floatMsg('/master/beat/subdiv/4', 0.25));
      source.handlePacket(_floatMsg('/master/beat/trigger/4', 1));
      await Future<void>.delayed(Duration.zero);
      expect(beats, isEmpty);
      expect(activity, hasLength(2));
      for (final s in subs) {
        await s.cancel();
      }
      source.dispose();
    });

    test('takes the tempo rkbx_link sends', () {
      final source = OscBeatSource();
      source.handlePacket(_floatMsg(OscBeatSource.bpmAddress, 127.3));
      expect(source.lastBpm, closeTo(127.3, 1e-4));
      source.dispose();
    });

    test('estimates the tempo from beat spacing until rkbx_link sends one', () {
      final source = OscBeatSource();
      final start = DateTime(2026);
      for (var i = 0; i < 5; i++) {
        source.handlePacket(
          _floatMsg(OscBeatSource.beatAddress, 1),
          now: start.add(Duration(milliseconds: 500 * i)),
        );
      }
      expect(source.lastBpm, closeTo(120, 0.01));
      // Once rkbx_link's own figure arrives, beat spacing no longer overrides it.
      source.handlePacket(_floatMsg(OscBeatSource.bpmAddress, 126), now: start.add(const Duration(seconds: 3)));
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 1), now: start.add(const Duration(milliseconds: 2600)));
      expect(source.lastBpm, 126);
      source.dispose();
    });

    test('a pause between beats does not report a bogus slow tempo', () {
      final source = OscBeatSource();
      final start = DateTime(2026);
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 1), now: start);
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 1), now: start.add(const Duration(milliseconds: 500)));
      expect(source.lastBpm, closeTo(120, 0.01));
      source.handlePacket(_floatMsg(OscBeatSource.beatAddress, 1), now: start.add(const Duration(seconds: 30)));
      expect(source.lastBpm, closeTo(120, 0.01));
      source.dispose();
    });
  });
}

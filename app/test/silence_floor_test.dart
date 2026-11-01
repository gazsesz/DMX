import 'dart:math' as math;

import 'package:dmx_controller/core/audio/beat_detector.dart';
import 'package:dmx_controller/core/widgets/silence_floor_slider.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A quiet room: tiny flux jitter, then one keyboard-click-sized spike
/// (about -30 dB, what the tablet measured) that stands far out of it.
Future<bool> _clickFiresBeat(double? floorDb, {double click = 0.03}) async {
  final service = BeatDetectorService();
  if (floorDb != null) service.silenceFloorDb = floorDb;
  final rng = math.Random(7);
  var beat = false;
  final sub = service.meterStream.listen((s) => beat |= s.isBeat);
  Map<BeatFrequencyBand, double> frame(double v) => {for (final b in BeatFrequencyBand.values) b: v};
  // Past the warmup (~1 s at ~11.6 ms a hop).
  for (var i = 0; i < 300; i++) {
    service.debugHandleFlux(frame(0.001 + rng.nextDouble() * 0.0005));
  }
  await Future<void>.delayed(Duration.zero);
  beat = false;
  service.debugHandleFlux(frame(click));
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  service.dispose();
  return beat;
}

void main() {
  test('with the floor off a click in a quiet room is a beat (the bug)', () async {
    expect(await _clickFiresBeat(null), isTrue);
  });

  test('a click below the floor is not a beat', () async {
    expect(await _clickFiresBeat(-20), isFalse);
  });

  test('a music-loud onset above the floor still is', () async {
    expect(await _clickFiresBeat(-20, click: 0.7), isTrue);
  });

  test('the bottom of the slider means off', () async {
    expect(await _clickFiresBeat(BeatDetectorService.silenceFloorOff), isTrue);
  });

  testWidgets('the slider sets the floor and remembers it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = BeatDetectorService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SilenceFloorSlider(service: service))));
    expect(find.text('Off'), findsOneWidget);

    await tester.drag(find.byKey(const Key('silence-floor-slider')), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(service.silenceFloorEnabled, isTrue);
    expect(find.text('${service.silenceFloorDb.round()} dB'), findsOneWidget);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getDouble(prefBeatSilenceFloor), service.silenceFloorDb);
    service.dispose();
  });
}

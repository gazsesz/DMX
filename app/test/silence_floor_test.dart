import 'package:dmx_controller/core/audio/beat_detector.dart';
import 'package:dmx_controller/core/audio/music_presence.dart';
import 'package:dmx_controller/core/widgets/silence_floor_slider.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hop = 11.6;
const _floor = -40.0;

/// Feeds [seconds] of frames: [base] dBFS, with a [peak] burst of
/// [burstMs] every [everyMs] (a click, a cough, a kick).
bool? _feed(MusicPresence p, double seconds, double base, {double? peak, int burstMs = 30, int everyMs = 500}) {
  bool? out;
  final frames = (seconds * 1000 / _hop).round();
  for (var i = 0; i < frames; i++) {
    final t = (i * _hop).round();
    final inBurst = peak != null && t % everyMs < burstMs;
    out = p.add(inBurst ? peak : base, _floor, _hop);
  }
  return out;
}

void main() {
  group('MusicPresence', () {
    test('unknown until the window has filled', () {
      final p = MusicPresence();
      expect(_feed(p, 1, -20), isNull);
      expect(_feed(p, 1.1, -20), isTrue);
    });

    test('keyboard clicks and coughs in a quiet room are not music', () {
      final p = MusicPresence();
      expect(_feed(p, 5, -60, peak: -5, burstMs: 30, everyMs: 200), isFalse, reason: 'fast typing');
      expect(_feed(p, 5, -60, peak: 0, burstMs: 300, everyMs: 2000), isFalse, reason: 'a cough every 2 s');
    });

    test('music is music even between the kicks, and its end is caught', () {
      final p = MusicPresence();
      expect(_feed(p, 4, -30, peak: -12, burstMs: 80, everyMs: 500), isTrue);
      expect(_feed(p, 1, -60), isTrue, reason: 'one second of a break keeps it');
      expect(_feed(p, 2, -60), isFalse);
    });

    test('moving the floor re-judges the whole window', () {
      final p = MusicPresence();
      for (var i = 0; i < 300; i++) {
        p.add(-45, -50, _hop);
      }
      expect(p.present, isTrue);
      expect(p.add(-45, -40, _hop), isFalse);
    });
  });

  test('the detector reports presence only while the floor is on', () async {
    final service = BeatDetectorService();
    final seen = <bool?>[];
    final sub = service.musicPresenceStream.listen(seen.add);
    for (var i = 0; i < 300; i++) {
      service.debugHandleLevel(-20);
    }
    expect(service.musicPresent, isNull);
    service.silenceFloorDb = -40;
    for (var i = 0; i < 300; i++) {
      service.debugHandleLevel(-20);
    }
    expect(service.musicPresent, isTrue);
    for (var i = 0; i < 300; i++) {
      service.debugHandleLevel(-70);
    }
    expect(service.musicPresent, isFalse);
    service.silenceFloorDb = BeatDetectorService.silenceFloorOff;
    service.debugHandleLevel(-70);
    expect(service.musicPresent, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true, false, null]);
    await sub.cancel();
    service.dispose();
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

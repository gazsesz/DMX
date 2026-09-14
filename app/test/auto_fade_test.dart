import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/tempo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auto-fade ties the cross-fade to the tempo, so the arithmetic has to
/// hold at both ends of the range — a fade longer than the step it belongs
/// to would leave the rig permanently mid-transition.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  // Local functions, not getters: Dart has no local getter declarations.
  TempoNotifier notifier() => container.read(tempoProvider.notifier);
  TempoState tempo() => container.read(tempoProvider);

  test('off by default, and the manual fade is what counts', () {
    notifier().setFadeSeconds(0.4);
    expect(tempo().autoFade, isFalse);
    expect(tempo().effectiveFadeSeconds, closeTo(0.4, 1e-9));
  });

  test('on, the fade is a fraction of the step and ignores the manual value', () {
    notifier().setFadeSeconds(0.4);
    notifier().setAutoFade(true);
    notifier().setAutoFadeAmount(0.5);
    notifier().setStepSeconds(1.0);
    expect(tempo().effectiveFadeSeconds, closeTo(tempo().autoFadeRatio, 1e-9));
    expect(tempo().effectiveFadeSeconds, isNot(closeTo(0.4, 1e-9)));
  });

  test('slower music fades longer, faster music snaps tighter', () {
    notifier().setAutoFade(true);
    notifier().setBpm(60);
    final slow = tempo().effectiveFadeSeconds;
    notifier().setBpm(160);
    final fast = tempo().effectiveFadeSeconds;
    expect(slow, greaterThan(fast));
  });

  test('the amount scales how much of the step the fade takes', () {
    notifier().setAutoFade(true);
    notifier().setStepSeconds(1.0);
    notifier().setAutoFadeAmount(0);
    final gentle = tempo().effectiveFadeSeconds;
    notifier().setAutoFadeAmount(1);
    final heavy = tempo().effectiveFadeSeconds;
    expect(heavy, greaterThan(gentle));
    // Never the whole step: the next fade would start as the last ended and
    // no look would ever fully land.
    expect(heavy, lessThan(1.0));
    // And never zero, or the switch would appear to do nothing.
    expect(gentle, greaterThan(0));
  });

  test('the fade never outlasts its own step, at any tempo or amount', () {
    notifier().setAutoFade(true);
    notifier().setAutoFadeAmount(1);
    for (final bpm in [20.0, 60.0, 120.0, 200.0, 300.0]) {
      notifier().setBpm(bpm);
      expect(
        tempo().effectiveFadeSeconds,
        lessThan(tempo().stepSeconds),
        reason: '$bpm BPM',
      );
    }
  });

  test('the amount is clamped rather than trusted', () {
    notifier().setAutoFadeAmount(-5);
    expect(tempo().autoFadeAmount, 0);
    notifier().setAutoFadeAmount(5);
    expect(tempo().autoFadeAmount, 1);
  });

  group('beat rate', () {
    test('only the two-step rates insert an off-beat step', () {
      expect(BeatRate.half.hasOffBeatStep, isFalse);
      expect(BeatRate.normal.hasOffBeatStep, isFalse);
      expect(BeatRate.doubled.hasOffBeatStep, isTrue);
      // Flash is a two-step rate too — the second step is what turns the
      // lamps back off.
      expect(BeatRate.flash.hasOffBeatStep, isTrue);
    });

    test('every rate has its own label for the segmented button', () {
      final labels = [for (final rate in BeatRate.values) rate.label];
      expect(labels.toSet().length, BeatRate.values.length);
      expect(labels, contains('Flash'));
    });

    test('the flash length defaults to something that reads as light', () {
      final length = container.read(flashLengthProvider);
      expect(length.inMilliseconds, greaterThanOrEqualTo(20));
      // Short enough to be dark again before the next beat, even at a slow
      // 60 BPM (a full second per beat).
      expect(length.inMilliseconds, lessThan(500));
    });
  });

  test('turning it off restores the fade that was set by hand', () {
    notifier().setFadeSeconds(0.4);
    notifier().setAutoFade(true);
    notifier().setStepSeconds(3.0);
    expect(tempo().effectiveFadeSeconds, isNot(closeTo(0.4, 1e-9)));
    notifier().setAutoFade(false);
    expect(tempo().effectiveFadeSeconds, closeTo(0.4, 1e-9));
  });
}

import 'package:dmx_controller/core/audio/beat_detector.dart';
import 'package:dmx_controller/core/audio/beat_tuning.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const tuned = BeatTuning(sensitivity: 0.8, band: BeatFrequencyBand.kickTight, adaptSpeed: BeatAdaptSpeed.fast);

  test('BeatTuning round-trips, and nonsense falls back to the defaults', () {
    expect(BeatTuning.fromJson(tuned.toJson()), tuned);
    final odd = BeatTuning.fromJson({'sensitivity': 7, 'band': 'cowbell', 'adaptSpeed': 3});
    expect(odd, const BeatTuning(sensitivity: 1.0));
    expect(beatTuningFromPref(null), const BeatTuning());
    expect(beatTuningFromPref('{broken'), const BeatTuning());
  });

  test('a project carries its tuning; an old one has none', () {
    final back = ProjectData.fromJson(
      const ProjectData(
        name: 'Club',
        settings: ArtNetSettings(),
        universes: [],
        customFixtureProfiles: [],
        patchedFixtures: [],
        scenes: [],
        banks: [],
        chases: [],
        beatTuning: tuned,
      ).toJson(),
      builtIns: const [],
    );
    expect(back.beatTuning, tuned);
    expect(
      ProjectData.fromJson(
        const ProjectData(
          name: 'Old',
          settings: ArtNetSettings(),
          universes: [],
          customFixtureProfiles: [],
          patchedFixtures: [],
          scenes: [],
          banks: [],
          chases: [],
        ).toJson(),
        builtIns: const [],
      ).beatTuning,
      isNull,
    );
  });

  group('beatTuningProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts from the remembered tuning and drives the detector', () async {
      final container = ProviderContainer(overrides: [initialBeatTuningProvider.overrideWithValue(tuned)]);
      addTearDown(container.dispose);
      final detector = container.read(beatDetectorProvider);
      expect(detector.sensitivity, 0.8);
      expect(detector.frequencyBand, BeatFrequencyBand.kickTight);

      container.read(beatTuningProvider.notifier).setBand(BeatFrequencyBand.kick);
      expect(detector.frequencyBand, BeatFrequencyBand.kick);
      await Future<void>.delayed(Duration.zero);
      final saved = (await SharedPreferences.getInstance()).getString(prefBeatTuning);
      expect(beatTuningFromPref(saved).band, BeatFrequencyBand.kick);
    });

    test('a project\'s tuning wins on load; an old project keeps the tablet\'s', () {
      final container = ProviderContainer(overrides: [initialBeatTuningProvider.overrideWithValue(tuned)]);
      addTearDown(container.dispose);
      final notifier = container.read(beatTuningProvider.notifier);
      notifier.load(null);
      expect(container.read(beatTuningProvider), tuned);
      notifier.load(const BeatTuning());
      expect(container.read(beatTuningProvider), const BeatTuning());
      expect(container.read(beatDetectorProvider).adaptSpeed, BeatAdaptSpeed.normal);
    });
  });
}

import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/generator/program_generator.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);
  final rgbPar = FixtureProfile(
    id: 'rgb-par',
    name: 'RGB PAR',
    category: FixtureCategory.rgb,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
      FixtureChannel(offset: 2, function: ChannelFunction.green),
      FixtureChannel(offset: 3, function: ChannelFunction.blue),
    ],
  );
  List<PatchedFixture> lamps(int n) => [
    for (var i = 0; i < n; i++)
      PatchedFixture(id: 'lamp-$i', label: 'Lamp ${i + 1}', profile: rgbPar, universeId: 'u1', startChannel: i * 4),
  ];

  group('Running Strobe', () {
    /// Which lamps are lit in each flash scene (the gap scenes in between
    /// skipped), as lamp indexes.
    List<List<int>> flashes(List<Scene> scenes, List<PatchedFixture> fixtures) => [
      for (var s = 0; s < scenes.length; s += 2)
        [
          for (var f = 0; f < fixtures.length; f++)
            if (scenes[s].fixtureValues[fixtures[f].id]![0] == 255) f,
        ],
    ];

    List<Scene> strobe(List<PatchedFixture> fixtures, int group, StrobeDirection direction) {
      var n = 0;
      return generateScenes(
        effect: GeneratorEffect.runningStrobe,
        colors: const [
          [255, 255, 255],
        ],
        fixtures: fixtures,
        count: 1,
        idGenerator: () => 's${n++}',
        namePrefix: 'Strobe',
        strobeGroupSize: group,
        strobeDirection: direction,
      );
    }

    test('one lamp at a time, to the right, with a dark gap after each flash', () {
      final fixtures = lamps(4);
      final scenes = strobe(fixtures, 1, StrobeDirection.right);
      expect(scenes, hasLength(8));
      expect(flashes(scenes, fixtures), [[0], [1], [2], [3]]);
      for (var s = 1; s < scenes.length; s += 2) {
        expect([for (final f in fixtures) scenes[s].fixtureValues[f.id]![0]], [0, 0, 0, 0]);
      }
    });

    test('two lamps at a time, to the left', () {
      final fixtures = lamps(4);
      expect(flashes(strobe(fixtures, 2, StrobeDirection.left), fixtures), [[2, 3], [0, 1]]);
    });

    test('bounce turns at the ends without flashing them twice', () {
      final fixtures = lamps(4);
      expect(flashes(strobe(fixtures, 1, StrobeDirection.bounce), fixtures), [[0], [1], [2], [3], [2], [1]]);
      expect(runningStrobeSceneCount(4, 1, StrobeDirection.bounce), 12);
    });

    test('an odd lamp out still gets its own flash', () {
      final fixtures = lamps(5);
      expect(flashes(strobe(fixtures, 2, StrobeDirection.right), fixtures), [[0, 1], [2, 3], [4]]);
    });
  });

  test('a Beat Flash fade-out changed while the bank runs inside a chase lands without a restart', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final beats = StreamController<DateTime>.broadcast();
    final fixtures = lamps(1);
    var counter = 0;
    final scenes = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 's${counter++}');
    var banks = [Bank(id: 'flash', name: 'Flash', sceneSlots: [scenes.first.id, scenes.last.id], isBeatFlash: true)];
    final player = ChasePlayer();
    unawaited(player.play(
      chase: const Chase(id: 'c', name: 'Show', steps: [ChaseStep(bankId: 'flash')], beatSync: true),
      scenes: scenes,
      banks: banks,
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      beatStream: beats.stream,
      flashLength: const Duration(milliseconds: 40),
      liveBanks: () => banks,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 40));
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.getChannelValue(universe, 0), 0, reason: 'no fade-out yet: a hard cut');

    // The bank is edited — a new list, as every provider update is.
    banks = [banks.first.copyWith(flashFadeOutMs: 400)];
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final mid = service.getChannelValue(universe, 0);
    expect(mid, greaterThan(0), reason: 'the new fade-out should be easing the flash down');
    expect(mid, lessThan(255));

    player.stop();
    await beats.close();
    await service.disconnect();
  });
}

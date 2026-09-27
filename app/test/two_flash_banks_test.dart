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
    ],
  );
  final fixtures = [
    for (var i = 0; i < 2; i++)
      PatchedFixture(id: 'lamp-$i', label: 'Lamp $i', profile: rgbPar, universeId: 'u1', startChannel: i * 2),
  ];

  test('two Beat Flash banks back to back in a chase both flash, at the app-wide 1× rate', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final beats = StreamController<DateTime>.broadcast();
    var n = 0;
    final a = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'a${n++}');
    final b = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'b${n++}', color: const [255, 0, 0]);
    final banks = [
      Bank(id: 'A', name: 'A', sceneSlots: [a.first.id, a.last.id], isBeatFlash: true),
      Bank(id: 'B', name: 'B', sceneSlots: [b.first.id, b.last.id], isBeatFlash: true),
    ];
    final player = ChasePlayer(layerId: 'L1');
    final steps = <int>[];
    unawaited(player.play(
      chase: const Chase(
        id: 'c',
        name: 'Two flashes',
        steps: [
          ChaseStep(bankId: 'A', hold: Duration(milliseconds: 500), fade: Duration(milliseconds: 300)),
          ChaseStep(bankId: 'B', hold: Duration(milliseconds: 500), fade: Duration(milliseconds: 300)),
        ],
      ),
      scenes: [...a, ...b],
      banks: banks,
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      beatStream: beats.stream,
      liveBeatSync: () => true,
      liveBanks: () => banks,
      beatRate: BeatRate.normal,
      liveBeatRate: () => BeatRate.normal,
      flashLength: const Duration(milliseconds: 40),
      fadeOverride: () => const Duration(milliseconds: 300),
      onStep: steps.add,
    ));

    int dimmer() => service.getChannelValue(universe, 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    for (var beat = 0; beat < 4; beat++) {
      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(dimmer(), 255, reason: 'beat $beat: lit on the beat (steps so far $steps)');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(dimmer(), 0, reason: 'beat $beat: dark again after the flash (steps so far $steps)');
    }
    player.stop();
    await beats.close();
    await service.disconnect();
  });

  test('without beat sync a flash bank still flashes: short lit step, dark for the hold', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    var n = 0;
    final a = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'a${n++}');
    final banks = [Bank(id: 'A', name: 'A', sceneSlots: [a.first.id, a.last.id], isBeatFlash: true)];
    final player = ChasePlayer();
    final litFor = <int>[];
    var litSince = -1;
    final clock = Stopwatch()..start();
    unawaited(player.play(
      chase: const Chase(
        id: 'c',
        name: 'Timed',
        steps: [ChaseStep(bankId: 'A', hold: Duration(milliseconds: 250), fade: Duration(milliseconds: 200))],
      ),
      scenes: a,
      banks: banks,
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      flashLength: const Duration(milliseconds: 40),
      onStep: (i) {
        if (i == 1) {
          litSince = clock.elapsedMilliseconds;
        } else if (litSince >= 0) {
          litFor.add(clock.elapsedMilliseconds - litSince);
        }
      },
    ));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    player.stop();
    expect(litFor, isNotEmpty);
    for (final ms in litFor) {
      expect(ms, lessThan(150), reason: 'the lit step should be a short flash, not the 250 ms hold');
    }
    await service.disconnect();
  });

  group('a flash bank overrides the chase\'s own hold', () {
    late ArtNetService service;
    late List<Scene> scenes;
    late List<Bank> banks;
    setUp(() async {
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      var n = 0;
      scenes = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'a${n++}');
      banks = [Bank(id: 'A', name: 'A', sceneSlots: [scenes.first.id, scenes.last.id], isBeatFlash: true)];
    });
    tearDown(() => service.disconnect());

    // A chase with a long hold and its own beat sync off — what used to
    // need the hold dragged to zero before the flash would show.
    const chase = Chase(
      id: 'c',
      name: 'Long hold',
      steps: [ChaseStep(bankId: 'A', hold: Duration(seconds: 3), fade: Duration(milliseconds: 500))],
    );

    test('beats coming in: it flashes on them, chase beat sync or not', () async {
      final beats = StreamController<DateTime>.broadcast();
      final player = ChasePlayer();
      unawaited(player.play(
        chase: chase,
        scenes: scenes,
        banks: banks,
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
        beatStream: beats.stream,
        liveBeatSync: () => false,
        liveBeatAvailable: () => true,
        flashLength: const Duration(milliseconds: 40),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      for (var beat = 0; beat < 3; beat++) {
        beats.add(DateTime.now());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(service.getChannelValue(universe, 0), 255, reason: 'beat $beat: lit on the beat');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(service.getChannelValue(universe, 0), 0, reason: 'beat $beat: dark after the flash');
      }
      player.stop();
      await beats.close();
    });

    test('no beats: the dark step lasts a beat at the show tempo, not the chase hold', () async {
      final player = ChasePlayer();
      var flashes = 0;
      unawaited(player.play(
        chase: chase,
        scenes: scenes,
        banks: banks,
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
        beatStream: const Stream<DateTime>.empty(),
        liveBeatSync: () => false,
        liveBeatAvailable: () => false,
        liveFlashGap: () => const Duration(milliseconds: 150),
        flashLength: const Duration(milliseconds: 40),
        onStep: (i) {
          if (i == 1) flashes++;
        },
      ));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      player.stop();
      expect(flashes, greaterThanOrEqualTo(4), reason: 'a flash about every 190 ms, not every 3 s');
    });
  });

  test('a flash bank after a 2× bank in the same chase still flashes on the beat', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final beats = StreamController<DateTime>.broadcast();
    var n = 0;
    final flash = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'f${n++}');
    final plain = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'p${n++}', color: const [0, 0, 255]);
    final banks = [
      // Three slots at 2×: leaves the on/off count odd going into the flash.
      Bank(id: 'P', name: 'Plain', sceneSlots: [plain.last.id, plain.first.id, plain.last.id]),
      Bank(id: 'F', name: 'Flash', sceneSlots: [flash.first.id, flash.last.id], isBeatFlash: true),
    ];
    final player = ChasePlayer();
    final steps = <int>[];
    unawaited(player.play(
      chase: const Chase(
        id: 'c',
        name: 'Mix',
        steps: [ChaseStep(bankId: 'P', fade: Duration.zero), ChaseStep(bankId: 'F', fade: Duration.zero)],
      ),
      scenes: [...flash, ...plain],
      banks: banks,
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      beatStream: beats.stream,
      liveBeatSync: () => true,
      beatRate: BeatRate.doubled,
      flashLength: const Duration(milliseconds: 40),
      onStep: steps.add,
    ));
    // Beat through the plain bank until the flash's dark step (index 3) is up.
    for (var i = 0; i < 6 && (steps.isEmpty || steps.last != 3); i++) {
      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(steps.last, 3, reason: 'reached the flash bank');
    expect(service.getChannelValue(universe, 0), 0, reason: 'dark step waits for the beat');
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.getChannelValue(universe, 0), 255, reason: 'lit on the beat');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(steps.last, isNot(4), reason: 'the lit step is a short flash, not held to the next beat');
    player.stop();
    await beats.close();
    await service.disconnect();
  });
}

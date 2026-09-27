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
  final fixtures = [
    for (var i = 0; i < 4; i++)
      PatchedFixture(id: 'lamp-$i', label: 'Lamp ${i + 1}', profile: rgbPar, universeId: 'u1', startChannel: i * 4),
  ];

  late ArtNetService service;

  setUp(() async {
    service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
  });

  tearDown(() => service.disconnect());

  int dimmer(int lamp) => service.getChannelValue(universe, lamp * 4);

  group('ArtNetService layer arbitration', () {
    test('the layer started last wins a shared channel', () {
      service.claimLayer('L1');
      service.claimLayer('L2');
      service.setLayerChannel(universe, 0, 50, 'L2');
      service.setLayerChannel(universe, 0, 200, 'L1');
      expect(service.getChannelValue(universe, 0), 50, reason: 'L1 is older, it can\'t take L2\'s channel');
    });

    test('a channel the newer layer lets go of falls back to the older one', () {
      service.claimLayer('L1');
      service.setLayerChannel(universe, 0, 200, 'L1');
      service.claimLayer('L2');
      service.setLayerChannel(universe, 0, 50, 'L2');
      expect(service.getChannelValue(universe, 0), 50);
      service.releaseLayer('L2');
      expect(service.getChannelValue(universe, 0), 200);
    });

    test('with no other layer asking, a released channel keeps its level', () {
      service.claimLayer('L2');
      service.setLayerChannel(universe, 3, 80, 'L2');
      service.releaseLayer('L2');
      expect(service.getChannelValue(universe, 3), 80);
    });

    test('re-starting an older layer makes it the newest', () {
      service.claimLayer('L1');
      service.claimLayer('L2');
      service.setLayerChannel(universe, 0, 50, 'L2');
      service.claimLayer('L1');
      service.setLayerChannel(universe, 0, 200, 'L1');
      expect(service.getChannelValue(universe, 0), 200);
    });
  });

  group('layered ChasePlayers', () {
    Scene dimmerScene(String id, Map<int, int> byLamp) => Scene(
      id: id,
      name: id,
      fixtureValues: {for (final e in byLamp.entries) 'lamp-${e.key}': {0: e.value}},
    );

    Future<void> run(ChasePlayer player, Scene scene) {
      unawaited(player.play(
        chase: Chase(id: scene.id, name: scene.id, steps: [ChaseStep(sceneId: scene.id, hold: const Duration(seconds: 5), fade: Duration.zero)]),
        scenes: [scene],
        banks: const [],
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
      ));
      return Future<void>.delayed(const Duration(milliseconds: 40));
    }

    test('a program started later overrides the lamps it shares, and hands them back on stop', () async {
      final l1 = ChasePlayer(layerId: 'L1');
      final l2 = ChasePlayer(layerId: 'L2');
      await run(l1, dimmerScene('all', {0: 100, 1: 100, 2: 100, 3: 100}));
      await run(l2, dimmerScene('one', {0: 255}));
      expect([for (var i = 0; i < 4; i++) dimmer(i)], [255, 100, 100, 100]);

      l2.stop();
      expect(dimmer(0), 100, reason: 'Layer 1 is still playing lamp 1 — it gets it straight back');
      l1.stop();
    });

    test('switching a layer to a new program frees lamps the new one doesn\'t use', () async {
      final l1 = ChasePlayer(layerId: 'L1');
      final l2 = ChasePlayer(layerId: 'L2');
      await run(l1, dimmerScene('base', {0: 100, 1: 100}));
      await run(l2, dimmerScene('both', {0: 255, 1: 255}));
      await run(l2, dimmerScene('first', {0: 30}));
      expect(dimmer(0), 30);
      expect(dimmer(1), 100, reason: 'lamp 2 went back to Layer 1 when Layer 2 stopped using it');
      l1.stop();
      l2.stop();
    });
  });

  group('Beat Flash on its own', () {
    late StreamController<DateTime> beats;
    setUp(() => beats = StreamController<DateTime>.broadcast());
    tearDown(() => beats.close());

    test('a Beat Flash bank flashes at the Flash rate even when the app-wide rate is 1×', () async {
      var counter = 0;
      final scenes = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 's${counter++}');
      final bank = Bank(id: 'flash', name: 'Flash', sceneSlots: [scenes.first.id, scenes.last.id], isBeatFlash: true);
      final player = ChasePlayer();
      unawaited(player.play(
        chase: const Chase(id: 'c', name: 'c', steps: [ChaseStep(bankId: 'flash')], beatSync: true),
        scenes: scenes,
        banks: [bank],
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
        beatStream: beats.stream,
        beatRate: BeatRate.normal,
        flashLength: const Duration(milliseconds: 40),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(dimmer(0), 255);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(dimmer(0), 0, reason: 'back to dark after the flash length, not a whole beat later');
      player.stop();
    });

    test('a flash trimmed to one lamp leaves the other lamps alone between beats', () async {
      var counter = 0;
      final full = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 's${counter++}');
      // The "Up" scene edited down to lamp 1; "Out" still names the rig.
      final up = full.last.copyWith(fixtureValues: {'lamp-0': full.last.fixtureValues['lamp-0']!});
      final bank = Bank(id: 'flash', name: 'Flash', sceneSlots: [full.first.id, up.id], isBeatFlash: true);
      for (var lamp = 1; lamp < 4; lamp++) {
        service.setChannel(universe, lamp * 4, 180, send: false);
      }
      final player = ChasePlayer();
      unawaited(player.play(
        chase: const Chase(id: 'c', name: 'c', steps: [ChaseStep(bankId: 'flash')], beatSync: true),
        scenes: [full.first, up],
        banks: [bank],
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
        beatStream: beats.stream,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect([for (var i = 0; i < 4; i++) dimmer(i)], [0, 180, 180, 180]);
      player.stop();
    });
  });

  test('a chase following the beat-sync switch picks it up live, both ways', () async {
    final beats = StreamController<DateTime>.broadcast();
    var synced = false;
    final steps = <int>[];
    final a = Scene(id: 'a', name: 'a', fixtureValues: const {'lamp-0': {0: 10}});
    final b = Scene(id: 'b', name: 'b', fixtureValues: const {'lamp-0': {0: 20}});
    final player = ChasePlayer();
    unawaited(player.play(
      chase: const Chase(
        id: 'c',
        name: 'c',
        steps: [
          ChaseStep(sceneId: 'a', hold: Duration(milliseconds: 30), fade: Duration.zero),
          ChaseStep(sceneId: 'b', hold: Duration(milliseconds: 30), fade: Duration.zero),
        ],
      ),
      scenes: [a, b],
      banks: const [],
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      beatStream: beats.stream,
      liveBeatSync: () => synced,
      onStep: steps.add,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(steps.length, greaterThan(3), reason: 'beat sync off: running on the timers');

    synced = true;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final waiting = steps.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(steps.length, waiting, reason: 'beat sync on: waits for a beat');
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(steps.length, waiting + 1);

    synced = false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(steps.length, greaterThan(waiting + 3), reason: 'beat sync off again: no longer stuck on a beat');
    player.stop();
    await beats.close();
  });

  test('Rainbow Wave puts every lamp at a different point of the colour wheel', () {
    var counter = 0;
    final scenes = generateScenes(
      effect: GeneratorEffect.rainbowWave,
      colors: const [],
      fixtures: fixtures,
      count: 8,
      idGenerator: () => 's${counter++}',
      namePrefix: 'Wave',
    );
    final first = scenes.first.fixtureValues;
    final colours = {
      for (final f in fixtures) [first[f.id]![1], first[f.id]![2], first[f.id]![3]].join(','),
    };
    expect(colours, hasLength(4));
    // The plain sweep keeps the rig on one colour.
    final sweep = generateScenes(
      effect: GeneratorEffect.rainbow,
      colors: const [],
      fixtures: fixtures,
      count: 8,
      idGenerator: () => 's${counter++}',
      namePrefix: 'Sweep',
    ).first.fixtureValues;
    expect({for (final f in fixtures) sweep[f.id]![1]}, hasLength(1));
  });

  test('a bank\'s own timing survives a save and load, and is off by default', () {
    const bank = Bank(id: 'b', name: 'B', sceneSlots: [null], ownTiming: true, holdMs: 500, fadeMs: 120);
    final restored = Bank.fromJson(bank.toJson());
    expect(restored.ownTiming, isTrue);
    expect(restored.hold, const Duration(milliseconds: 500));
    expect(restored.fade, const Duration(milliseconds: 120));
    expect(Bank.fromJson(const {'id': 'x', 'name': 'X', 'sceneSlots': []}).ownTiming, isFalse);
  });
}

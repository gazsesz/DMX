import 'dart:async';
import 'dart:math';

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
      PatchedFixture(id: 'lamp-$i', label: 'Lamp $i', profile: rgbPar, universeId: 'u1', startChannel: i * 4),
  ];

  String rgbOf(Scene scene, PatchedFixture f) => [for (var o = 1; o <= 3; o++) scene.fixtureValues[f.id]![o]].join(',');

  ({List<Scene> scenes, List<String> slots}) build(FlashColorMode mode, {int flashes = 6}) {
    var n = 0;
    return buildRandomBeatFlash(
      fixtures: fixtures,
      idGenerator: () => 's${n++}',
      mode: mode,
      flashCount: flashes,
      random: Random(7),
    );
  }

  test('slots go dark, flash, dark, flash… with one shared dark scene', () {
    final built = build(FlashColorMode.randomSame);
    expect(built.slots, hasLength(12));
    final dark = built.scenes.first;
    for (var i = 0; i < built.slots.length; i += 2) {
      expect(built.slots[i], dark.id);
      expect(built.slots[i + 1], isNot(dark.id));
    }
    expect([for (final f in fixtures) dark.fixtureValues[f.id]![0]], [0, 0, 0, 0]);
  });

  test('random, all alike: every lamp shares the flash colour, and it changes flash to flash', () {
    final lits = build(FlashColorMode.randomSame).scenes.skip(1).toList();
    for (final lit in lits) {
      expect({for (final f in fixtures) rgbOf(lit, f)}, hasLength(1));
      expect([for (final f in fixtures) lit.fixtureValues[f.id]![0]], [255, 255, 255, 255]);
    }
    for (var k = 1; k < lits.length; k++) {
      expect(rgbOf(lits[k], fixtures.first), isNot(rgbOf(lits[k - 1], fixtures.first)));
    }
  });

  test('random, every lamp its own: neighbouring lamps differ within a flash', () {
    final lits = build(FlashColorMode.randomEach).scenes.skip(1).toList();
    for (final lit in lits) {
      for (var f = 1; f < fixtures.length; f++) {
        expect(rgbOf(lit, fixtures[f]), isNot(rgbOf(lit, fixtures[f - 1])));
      }
    }
  });

  test('played as a Beat Flash bank, each beat flashes the next colour', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final beats = StreamController<DateTime>.broadcast();
    final built = build(FlashColorMode.randomSame, flashes: 3);
    final bank = Bank(id: 'B', name: 'Random flash', sceneSlots: built.slots, isBeatFlash: true);
    final player = ChasePlayer();
    unawaited(player.play(
      chase: const Chase(id: 'c', name: 'c', steps: [ChaseStep(bankId: 'B')], beatSync: true),
      scenes: built.scenes,
      banks: [bank],
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      beatStream: beats.stream,
      flashLength: const Duration(milliseconds: 40),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final seen = <String>[];
    for (var beat = 0; beat < 3; beat++) {
      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.getChannelValue(universe, 0), 255);
      seen.add([for (var o = 1; o <= 3; o++) service.getChannelValue(universe, o)].join(','));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(service.getChannelValue(universe, 0), 0);
    }
    expect(seen, [for (final lit in built.scenes.skip(1)) rgbOf(lit, fixtures.first)]);
    player.stop();
    await beats.close();
    await service.disconnect();
  });
}

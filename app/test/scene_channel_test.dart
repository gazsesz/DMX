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

/// A Scene only ever specifies the channels it actually cares about, and
/// everything downstream (JSON, playback, the generator) has to respect
/// that — this is what lets a moving head's Position be driven by one
/// program while its Color/Beam is driven by another, on separate Layers,
/// without either one fighting the other for the same channel.
void main() {
  group('Scene JSON', () {
    test('reads the old full-array shape from before scenes could be sparse', () {
      final scene = Scene.fromJson({
        'id': 's1',
        'name': 'Old scene',
        'fixtureValues': {
          'f1': [10, 20, 30],
        },
      });
      expect(scene.fixtureValues['f1'], {0: 10, 1: 20, 2: 30});
    });

    test('round-trips the sparse shape, including a channel left out', () {
      const scene = Scene(
        id: 's2',
        name: 'Sparse scene',
        fixtureValues: {
          'mover': {2: 255, 4: 128},
        },
      );
      final decoded = Scene.fromJson(scene.toJson());
      expect(decoded.fixtureValues['mover'], {2: 255, 4: 128});
      // Offsets 0/1/3 were never in it — never invented on the way through.
      expect(decoded.fixtureValues['mover']!.containsKey(0), isFalse);
    });
  });

  group('ChannelFunction.attributeGroup', () {
    test('dimmer is its own group, scaled independently of everything else', () {
      expect(ChannelFunction.dimmer.attributeGroup, AttributeGroup.dimmer);
    });

    test('color emitters share one group', () {
      for (final f in [
        ChannelFunction.red,
        ChannelFunction.green,
        ChannelFunction.blue,
        ChannelFunction.white,
        ChannelFunction.amber,
        ChannelFunction.uv,
      ]) {
        expect(f.attributeGroup, AttributeGroup.color, reason: f.name);
      }
    });

    test('pan/tilt (fine included) share the Position group', () {
      for (final f in [ChannelFunction.pan, ChannelFunction.panFine, ChannelFunction.tilt, ChannelFunction.tiltFine]) {
        expect(f.attributeGroup, AttributeGroup.position, reason: f.name);
      }
    });

    test('gobo, gobo rotation and color wheel share the Beam group', () {
      for (final f in [ChannelFunction.gobo, ChannelFunction.goboRotation, ChannelFunction.colorWheel]) {
        expect(f.attributeGroup, AttributeGroup.beam, reason: f.name);
      }
    });

    test('everything else falls into Other', () {
      for (final f in [ChannelFunction.strobe, ChannelFunction.zoom, ChannelFunction.focus, ChannelFunction.autofade, ChannelFunction.generic]) {
        expect(f.attributeGroup, AttributeGroup.other, reason: f.name);
      }
    });
  });

  group('program generator leaves attributes it never touches alone', () {
    FixtureProfile moverProfile() => const FixtureProfile(
      id: 'mover',
      name: 'Mover',
      category: FixtureCategory.movingHead,
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.pan),
        FixtureChannel(offset: 1, function: ChannelFunction.tilt),
        FixtureChannel(offset: 2, function: ChannelFunction.dimmer),
        FixtureChannel(offset: 3, function: ChannelFunction.red),
        FixtureChannel(offset: 4, function: ChannelFunction.green),
        FixtureChannel(offset: 5, function: ChannelFunction.blue),
      ],
    );

    PatchedFixture patch(FixtureProfile p) =>
        PatchedFixture(id: 'f1', label: 'Mover 1', profile: p, universeId: 'u1', startChannel: 0);

    test('a pure color effect never mentions Pan/Tilt, so another Layer can own them', () {
      final scenes = generateScenes(
        effect: GeneratorEffect.colorChase,
        colors: const [
          [255, 0, 0],
        ],
        fixtures: [patch(moverProfile())],
        count: 2,
        idGenerator: () => 'scene-${DateTime.now().microsecondsSinceEpoch}',
        namePrefix: 'Test',
      );
      for (final scene in scenes) {
        final values = scene.fixtureValues['f1']!;
        expect(values.containsKey(0), isFalse, reason: 'pan (offset 0) must be left out');
        expect(values.containsKey(1), isFalse, reason: 'tilt (offset 1) must be left out');
        // Dimmer and color are the whole point of this effect, so they ARE set.
        expect(values.containsKey(2), isTrue);
      }
    });

    test('a move effect (Sweep) does set Pan/Tilt', () {
      final scenes = generateScenes(
        effect: GeneratorEffect.sweep,
        colors: const [
          [255, 255, 255],
        ],
        fixtures: [patch(moverProfile())],
        count: 4,
        idGenerator: () => 'scene-${DateTime.now().microsecondsSinceEpoch}',
        namePrefix: 'Test',
      );
      for (final scene in scenes) {
        final values = scene.fixtureValues['f1']!;
        expect(values.containsKey(0), isTrue);
        expect(values.containsKey(1), isTrue);
      }
    });
  });

  group('two Layers sharing one fixture never fight over a channel', () {
    const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);

    FixtureProfile moverProfile() => const FixtureProfile(
      id: 'mover',
      name: 'Mover',
      category: FixtureCategory.movingHead,
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.pan),
        FixtureChannel(offset: 1, function: ChannelFunction.tilt),
        FixtureChannel(offset: 2, function: ChannelFunction.red),
        FixtureChannel(offset: 3, function: ChannelFunction.green),
        FixtureChannel(offset: 4, function: ChannelFunction.blue),
      ],
    );

    late ArtNetService service;
    late PatchedFixture fixture;

    setUp(() async {
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      fixture = PatchedFixture(id: 'f1', label: 'Mover 1', profile: moverProfile(), universeId: 'u1', startChannel: 10);
    });

    tearDown(() async {
      await service.disconnect();
    });

    test('a color-only scene from one player leaves a position set by another untouched', () async {
      // Layer 2 already parked the head here.
      service.setChannel(universe, 10, 200); // pan
      service.setChannel(universe, 11, 90); // tilt

      // Layer 1 runs a color-only chase on the same fixture.
      const colorScene = Scene(
        id: 'red',
        name: 'Red',
        fixtureValues: {
          'f1': {2: 255, 3: 0, 4: 0},
        },
      );
      final chase = Chase(
        id: 'c1',
        name: 'Color chase',
        steps: const [ChaseStep(sceneId: 'red', hold: Duration(milliseconds: 20), fade: Duration.zero)],
      );
      final player = ChasePlayer();
      unawaited(
        player.play(
          chase: chase,
          scenes: const [colorScene],
          banks: const <Bank>[],
          patchedFixtures: [fixture],
          universes: const [universe],
          service: service,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      player.stop();

      expect(service.getChannelValue(universe, 12), 255, reason: 'red set by the color scene');
      expect(service.getChannelValue(universe, 10), 200, reason: 'pan left exactly as Layer 2 set it');
      expect(service.getChannelValue(universe, 11), 90, reason: 'tilt left exactly as Layer 2 set it');
    });
  });
}

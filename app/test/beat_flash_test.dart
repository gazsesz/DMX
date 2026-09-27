import 'package:dmx_controller/core/generator/program_generator.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

/// A flash bank is two scenes the player alternates between, so what's worth
/// pinning down is that the dark one is really dark on every kind of lamp,
/// and that the pair is in the order `BeatRate.flash` expects.
void main() {
  FixtureProfile profile(String id, List<ChannelFunction> functions) => FixtureProfile(
    id: id,
    name: id,
    category: FixtureCategory.generic,
    channels: [
      for (var i = 0; i < functions.length; i++) FixtureChannel(offset: i, function: functions[i]),
    ],
  );

  PatchedFixture patch(FixtureProfile p, int start) => PatchedFixture(
    id: 'f-$start',
    label: 'f$start',
    profile: p,
    universeId: 'u1',
    startChannel: start,
  );

  final rgbPar = profile('rgb-par', [
    ChannelFunction.dimmer,
    ChannelFunction.red,
    ChannelFunction.green,
    ChannelFunction.blue,
  ]);

  var counter = 0;
  String nextId() => 'id-${counter++}';

  setUp(() => counter = 0);

  group('buildBeatFlashScenes', () {
    test('puts the dark scene first, because flash lands the second step on the beat', () {
      final scenes = buildBeatFlashScenes(fixtures: [patch(rgbPar, 0)], idGenerator: nextId);

      expect(scenes, hasLength(2));
      expect(scenes.first.name, 'Beat Flash Out');
      expect(scenes.first.fixtureValues['f-0'], [0, 0, 0, 0]);
      expect(scenes.last.name, 'Beat Flash Up');
      expect(scenes.last.fixtureValues['f-0'], [255, 255, 255, 255]);
    });

    test('lights every patched lamp, not just the first', () {
      final scenes = buildBeatFlashScenes(
        fixtures: [patch(rgbPar, 0), patch(rgbPar, 4), patch(rgbPar, 8), patch(rgbPar, 12)],
        idGenerator: nextId,
      );

      expect(scenes.last.fixtureValues.keys, hasLength(4));
      for (final values in scenes.last.fixtureValues.values) {
        expect(values, [255, 255, 255, 255]);
      }
    });

    test('takes a dimmer-only lamp out too, instead of leaving it on at full', () {
      // The colour-only strobe effect can't: it zeroes R/G/B and hands the
      // dimmer 255 either way, which on a plain dimmer pack is a lamp that
      // never blinks.
      final dimmerPack = profile('pack', [ChannelFunction.dimmer]);
      final scenes = buildBeatFlashScenes(fixtures: [patch(dimmerPack, 0)], idGenerator: nextId);

      expect(scenes.first.fixtureValues['f-0'], [0]);
      expect(scenes.last.fixtureValues['f-0'], [255]);
    });

    test('parks a moving head at centre in both scenes so the beam holds still', () {
      final mover = profile('mover', [
        ChannelFunction.pan,
        ChannelFunction.tilt,
        ChannelFunction.dimmer,
        ChannelFunction.gobo,
      ]);
      final scenes = buildBeatFlashScenes(fixtures: [patch(mover, 0)], idGenerator: nextId);

      expect(scenes.first.fixtureValues['f-0'], [128, 128, 0, 0]);
      expect(scenes.last.fixtureValues['f-0'], [128, 128, 255, 0]);
    });

    test('only runs the white emitter up as far as the colour is white', () {
      final rgbw = profile('rgbw', [
        ChannelFunction.red,
        ChannelFunction.green,
        ChannelFunction.blue,
        ChannelFunction.white,
      ]);

      final white = buildBeatFlashScenes(fixtures: [patch(rgbw, 0)], idGenerator: nextId);
      expect(white.last.fixtureValues['f-0'], [255, 255, 255, 255]);

      final red = buildBeatFlashScenes(
        fixtures: [patch(rgbw, 0)],
        idGenerator: nextId,
        color: const [255, 0, 0],
      );
      expect(red.last.fixtureValues['f-0'], [255, 0, 0, 0]);
    });

    test('gives every scene its own id', () {
      final scenes = buildBeatFlashScenes(fixtures: [patch(rgbPar, 0)], idGenerator: nextId);
      expect(scenes.first.id, isNot(scenes.last.id));
    });

    test('has nothing to build without fixtures', () {
      expect(buildBeatFlashScenes(fixtures: const [], idGenerator: nextId), isEmpty);
    });
  });
}

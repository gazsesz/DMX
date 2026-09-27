import 'dart:typed_data';

import 'package:dmx_controller/core/playback/momentary_fx.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The momentary effects are the one place the app changes the light without
/// changing the show, so the thing worth pinning down is what they *don't*
/// touch: the frame they were handed, and the channels that aren't light.
void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);

  FixtureProfile profile(String id, List<ChannelFunction> functions) => FixtureProfile(
    id: id,
    name: id,
    category: FixtureCategory.generic,
    channels: [
      for (var i = 0; i < functions.length; i++) FixtureChannel(offset: i, function: functions[i]),
    ],
  );

  PatchedFixture patch(FixtureProfile p, int start, {String universeId = 'u1'}) => PatchedFixture(
    id: 'f-$start',
    label: 'f$start',
    profile: p,
    universeId: universeId,
    startChannel: start,
  );

  Uint8List frame(Map<int, int> values) {
    final buffer = Uint8List(512);
    values.forEach((channel, value) => buffer[channel] = value);
    return buffer;
  }

  group('blinderChannelsFor', () {
    test('opens the dimmer and runs the colours up on the same fixture', () {
      // The grand master picks one or the other; a blinder wants both.
      final wash = profile('wash', [
        ChannelFunction.dimmer,
        ChannelFunction.red,
        ChannelFunction.green,
        ChannelFunction.blue,
      ]);
      expect(blinderChannelsFor([patch(wash, 0)], [universe])['u1'], {0, 1, 2, 3});
    });

    test('leaves everything that is not light alone', () {
      final mover = profile('mover', [
        ChannelFunction.pan,
        ChannelFunction.tilt,
        ChannelFunction.gobo,
        ChannelFunction.colorWheel,
        ChannelFunction.strobe,
        ChannelFunction.dimmer,
      ]);
      expect(
        blinderChannelsFor([patch(mover, 0)], [universe])['u1'],
        {5},
        reason: 'the dimmer, and not the shutter beside it',
      );
    });

    test('keeps universes apart and drops what falls off the end', () {
      const second = UniverseConfig(id: 'u2', name: 'Universe 2', universe: 1);
      final par = profile('par', [ChannelFunction.dimmer]);
      final channels = blinderChannelsFor(
        [patch(par, 5), patch(par, 9, universeId: 'u2'), patch(par, 600)],
        [universe, second],
      );
      expect(channels['u1'], {5});
      expect(channels['u2'], {9});
    });
  });

  group('applyMomentaryFx', () {
    final live = frame({0: 100, 1: 200, 2: 0, 3: 50});

    test('with nothing held the frame goes out exactly as it came in', () {
      final out = applyMomentaryFx(frame: live, held: const {}, lit: true);
      expect(identical(out, live), isTrue, reason: 'and allocates nothing doing it');
    });

    test('the blinder runs its channels to full and leaves the rest', () {
      final out = applyMomentaryFx(
        frame: live,
        held: const {MomentaryFx.blinder},
        lit: true,
        blinderChannels: const {0, 1},
      );
      expect(out[0], 255);
      expect(out[1], 255);
      expect(out[3], 50, reason: 'a channel the blinder does not own');
      expect(live[0], 100, reason: 'the show frame itself is never written to');
    });

    test('the strobe takes light away on the dark half and only then', () {
      const held = {MomentaryFx.strobe};
      const intensity = {0};
      final lit = applyMomentaryFx(frame: live, held: held, lit: true, intensityChannels: intensity);
      expect(identical(lit, live), isTrue, reason: 'the lit half is the look, untouched');

      final dark = applyMomentaryFx(
        frame: live,
        held: held,
        lit: false,
        intensityChannels: intensity,
      );
      expect(dark[0], 0);
      expect(dark[1], 200, reason: 'colour is held while the intensity is chopped');
    });

    test('a freeze sends the frame it started from, not the one playing now', () {
      final frozen = frame({0: 10, 1: 20});
      final moved = frame({0: 77, 1: 88});
      final out = applyMomentaryFx(
        frame: moved,
        held: const {MomentaryFx.freeze},
        lit: true,
        frozen: frozen,
      );
      expect(out[0], 10);
      expect(out[1], 20);
      expect(moved[0], 77, reason: 'the show carried on underneath');
    });

    test('strobe over blinder is a white strobe', () {
      const held = {MomentaryFx.strobe, MomentaryFx.blinder};
      final lit = applyMomentaryFx(
        frame: live,
        held: held,
        lit: true,
        blinderChannels: const {0, 1},
        intensityChannels: const {0},
      );
      expect([lit[0], lit[1]], [255, 255]);

      final dark = applyMomentaryFx(
        frame: live,
        held: held,
        lit: false,
        blinderChannels: const {0, 1},
        intensityChannels: const {0},
      );
      expect(dark[0], 0, reason: 'the dark half is dark whatever else is held');
    });

    test('strobe over freeze chops the still, not what has moved on', () {
      final frozen = frame({0: 90});
      final out = applyMomentaryFx(
        frame: frame({0: 255}),
        held: const {MomentaryFx.freeze, MomentaryFx.strobe},
        lit: true,
        frozen: frozen,
        intensityChannels: const {0},
      );
      expect(out[0], 90);
      expect(frozen[0], 90, reason: 'the held frame survives being sent');
    });
  });
}

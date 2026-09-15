import 'package:dmx_controller/core/playback/master_channels.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The grand master must take light away and nothing else. Scaling a pan
/// channel would swing a moving head across the stage as you pull the
/// fader down, which is the kind of thing you find out on stage.
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

  test('a fixture with a dimmer is scaled on the dimmer alone', () {
    final mover = profile('mover', [
      ChannelFunction.pan,
      ChannelFunction.tilt,
      ChannelFunction.dimmer,
      ChannelFunction.red,
      ChannelFunction.gobo,
    ]);
    final channels = masterChannelsFor([patch(mover, 10)], [universe]);
    expect(channels['u1'], {12});
  });

  test('a fixture with no dimmer is scaled on its colour emitters', () {
    // Most cheap RGB pars: the colours are the intensity.
    final par = profile('par', [ChannelFunction.red, ChannelFunction.green, ChannelFunction.blue]);
    final channels = masterChannelsFor([patch(par, 0)], [universe]);
    expect(channels['u1'], {0, 1, 2});
  });

  test('pan, tilt, gobo and strobe are never touched', () {
    final mover = profile('mover', [
      ChannelFunction.pan,
      ChannelFunction.panFine,
      ChannelFunction.tilt,
      ChannelFunction.strobe,
      ChannelFunction.gobo,
      ChannelFunction.goboRotation,
      ChannelFunction.colorWheel,
      ChannelFunction.zoom,
      ChannelFunction.dimmer,
    ]);
    final channels = masterChannelsFor([patch(mover, 0)], [universe]);
    expect(channels['u1'], {8}, reason: 'only the dimmer at offset 8');
  });

  test('several fixtures land on their own patched addresses', () {
    final par = profile('par', [ChannelFunction.dimmer, ChannelFunction.red]);
    final channels = masterChannelsFor(
      [patch(par, 0), patch(par, 8), patch(par, 100)],
      [universe],
    );
    expect(channels['u1'], {0, 8, 100});
  });

  test('fixtures are kept apart by universe', () {
    const second = UniverseConfig(id: 'u2', name: 'Universe 2', universe: 1);
    final par = profile('par', [ChannelFunction.dimmer]);
    final channels = masterChannelsFor(
      [patch(par, 5), patch(par, 9, universeId: 'u2')],
      [universe, second],
    );
    expect(channels['u1'], {5});
    expect(channels['u2'], {9});
  });

  test('a fixture patched to a universe that no longer exists is ignored', () {
    final par = profile('par', [ChannelFunction.dimmer]);
    final channels = masterChannelsFor([patch(par, 5, universeId: 'gone')], [universe]);
    expect(channels['gone'], isNull);
  });

  test('a channel past the end of the universe is dropped, not wrapped', () {
    final wide = profile('wide', [ChannelFunction.dimmer]);
    final channels = masterChannelsFor([patch(wide, 511), patch(wide, 600)], [universe]);
    expect(channels['u1'], {511});
  });

  test('a fixture with neither dimmer nor colour contributes nothing', () {
    final smoke = profile('smoke', [ChannelFunction.generic]);
    final channels = masterChannelsFor([patch(smoke, 20)], [universe]);
    expect(channels['u1'], isEmpty);
  });
}

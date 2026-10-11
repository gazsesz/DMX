import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
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
  final head = FixtureProfile(
    id: 'head',
    name: 'Head',
    category: FixtureCategory.movingHead,
    channels: const [FixtureChannel(offset: 0, function: ChannelFunction.pan)],
  );
  final fixtures = [PatchedFixture(id: 'h', label: 'H', profile: head, universeId: 'u1', startChannel: 0)];

  for (final layered in [false, true]) {
    test('stopping mid-fade freezes the channel where it is (${layered ? 'layered' : 'plain'})', () async {
      final service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      final far = Scene(id: 'far', name: 'far', fixtureValues: {'h': {0: 200}});
      final player = layered ? ChasePlayer(layerId: 'L1') : ChasePlayer();
      unawaited(player.play(
        chase: const Chase(
          id: 'c',
          name: 'slow',
          steps: [ChaseStep(sceneId: 'far', hold: Duration(seconds: 5), fade: Duration(seconds: 3))],
        ),
        scenes: [far],
        banks: const [],
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      player.stop();
      final atStop = service.getChannelValue(universe, 0);
      expect(atStop, inInclusiveRange(10, 150), reason: 'part-way through the fade');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(service.getChannelValue(universe, 0), atStop, reason: 'nothing moves it on after the stop');
      await service.disconnect();
    });
  }
}

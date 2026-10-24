import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/song/song_scope.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);
  final par = FixtureProfile(
    id: 'par',
    name: 'PAR',
    category: FixtureCategory.rgb,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
      FixtureChannel(offset: 2, function: ChannelFunction.green),
    ],
  );
  final fixtures = [
    for (var i = 0; i < 4; i++)
      PatchedFixture(id: 'f$i', label: 'F$i', profile: par, universeId: 'u1', startChannel: i * 3),
  ];
  const groups = [
    FixtureGroup(id: 'front', name: 'Front', iconKey: 'x', fixtureIds: ['f0', 'f1']),
    FixtureGroup(id: 'back', name: 'Back', iconKey: 'x', fixtureIds: ['f2', 'f3']),
  ];

  group('scopeChannels', () {
    test('is every channel of every fixture in the chosen groups', () {
      final scope = scopeChannels(groupIds: ['front'], groups: groups, fixtures: fixtures)!;
      expect(scope['u1'], {0, 1, 2, 3, 4, 5});
    });

    test('several groups add up', () {
      final scope = scopeChannels(groupIds: ['front', 'back'], groups: groups, fixtures: fixtures)!;
      expect(scope['u1']!.length, 12);
    });

    test('no groups, a deleted group, or an empty group all mean the whole rig', () {
      expect(scopeChannels(groupIds: [], groups: groups, fixtures: fixtures), isNull);
      expect(scopeChannels(groupIds: ['gone'], groups: groups, fixtures: fixtures), isNull);
      const empty = FixtureGroup(id: 'e', name: 'E', iconKey: 'x', fixtureIds: []);
      expect(scopeChannels(groupIds: ['e'], groups: [empty], fixtures: fixtures), isNull);
    });
  });

  group('layer scope on the output', () {
    late ArtNetService service;

    setUp(() async {
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
    });

    tearDown(() => service.disconnect());

    test('a scoped layer only writes inside its scope', () {
      service.claimLayer('l1');
      service.setLayerScope('l1', {
        'u1': {0, 1, 2},
      });
      for (var ch = 0; ch < 6; ch++) {
        service.setLayerChannel(universe, ch, 200, 'l1');
      }
      expect([for (var ch = 0; ch < 6; ch++) service.getChannelValue(universe, ch)], [200, 200, 200, 0, 0, 0]);
    });

    test('a layer without a scope is unaffected', () {
      service.setLayerScope('l1', {
        'u1': {0},
      });
      service.setLayerChannel(universe, 5, 90, 'l2');
      expect(service.getChannelValue(universe, 5), 90);
    });

    test('lifting the scope lets the layer write everywhere again', () {
      service.setLayerScope('l1', {
        'u1': {0},
      });
      service.setLayerChannel(universe, 4, 70, 'l1');
      expect(service.getChannelValue(universe, 4), 0);
      service.setLayerScope('l1', null);
      service.setLayerChannel(universe, 4, 70, 'l1');
      expect(service.getChannelValue(universe, 4), 70);
      expect(service.layerIsScoped('l1'), isFalse);
    });

    test('scoping a layer hands back the channels it held outside the scope to the layer beneath', () {
      service.claimLayer('under');
      service.setLayerChannel(universe, 4, 30, 'under');
      service.claimLayer('l1');
      service.setLayerChannel(universe, 4, 250, 'l1');
      service.setLayerChannel(universe, 0, 250, 'l1');
      expect(service.getChannelValue(universe, 4), 250);

      service.setLayerScope('l1', {
        'u1': {0},
      });
      expect(service.getChannelValue(universe, 4), 30, reason: 'out of scope: back to the layer underneath');
      expect(service.getChannelValue(universe, 0), 250, reason: 'in scope: kept');
    });
  });
}

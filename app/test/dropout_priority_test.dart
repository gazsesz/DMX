import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/dimmer_dropout_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which dropout wins when the dock's and a chase's own are both on.
void main() {
  const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
  const profile = FixtureProfile(
    id: 'dim',
    name: 'Dimmer',
    category: FixtureCategory.generic,
    channels: [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
  );
  // Par 1 is lit by the chase on layer "a", par 2 by something on layer "b".
  final pars = [
    PatchedFixture(id: 'p1', label: 'P1', profile: profile, universeId: 'u1', startChannel: 0),
    PatchedFixture(id: 'p2', label: 'P2', profile: profile, universeId: 'u1', startChannel: 1),
  ];

  late ArtNetService service;
  late StreamController<DateTime> beats;
  late DimmerDropoutController controller;

  setUp(() {
    service = ArtNetService();
    beats = StreamController<DateTime>.broadcast();
    controller = DimmerDropoutController(service, beatEvents: () => beats.stream, beatsListening: () => true);
    service.claimLayer('a');
    service.setLayerChannel(universe, 0, 200, 'a');
    service.claimLayer('b');
    service.setLayerChannel(universe, 1, 200, 'b');
    controller.refreshScope(pars, const [universe]);
  });

  tearDown(() {
    controller.dispose();
    beats.close();
  });

  DropoutSettings every(int n) => DropoutSettings(enabled: true, onBeat: true, beatEvery: n, lengthMs: 40);

  Future<Set<int>> beat() async {
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return service.darkChannels?.call(universe) ?? const {};
  }

  Future<void> lightBack() => Future<void>.delayed(const Duration(milliseconds: 80));

  test('Deck (default): the chase\'s own waits while the dock\'s is on, and runs again once it is off', () async {
    expect(controller.priority, DropoutPriority.deck);
    controller.setChaseDropout('a', every(1));
    controller.update(every(2));
    expect(await beat(), isEmpty, reason: 'the chase lane is held back');
    await lightBack();
    expect(await beat(), {0, 1}, reason: 'the dock\'s cuts everything');
    await lightBack();

    controller.update(const DropoutSettings());
    expect(await beat(), {0}, reason: 'dock off: the chase\'s own runs on its layer');
  });

  test('Both: each runs on its own clock', () async {
    controller.priority = DropoutPriority.both;
    controller.setChaseDropout('a', every(3));
    controller.update(every(1));
    expect(await beat(), {0, 1});
  });

  test('Chase: the dock\'s leaves the chase\'s layer alone and still cuts the rest', () async {
    controller.priority = DropoutPriority.chase;
    controller.setChaseDropout('a', every(3));
    controller.update(every(1));
    expect(await beat(), {1});
    await lightBack();
    await beat();
    expect(await beat(), {0, 1}, reason: 'the chase\'s own cuts its layer on its 3rd beat');
    await lightBack();

    controller.setChaseDropout('a', null);
    expect(await beat(), {0, 1}, reason: 'chase stopped: the dock\'s has every layer again');
  });
}

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
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two Beat Flash banks dropped into one chase — the way you build a show
/// out of them — still has to flash on the beat, and on *every* beat rather
/// than only while the first bank's turn comes round.
///
/// A chase fired from the Chases list used to reach the player with no beat
/// stream at all, so this look ran on its step timers and drifted against
/// the music. The player is driven here with a beat stream under the test's
/// control, which is the wiring that was missing.
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

  // Four lamps, patched back to back — one 4-channel block each.
  final fixtures = [
    for (var i = 0; i < 4; i++)
      PatchedFixture(
        id: 'lamp-$i',
        label: 'Lamp ${i + 1}',
        profile: rgbPar,
        universeId: 'u1',
        startChannel: i * 4,
      ),
  ];

  late ArtNetService service;
  late StreamController<DateTime> beats;
  late ChasePlayer player;

  setUp(() async {
    service = ArtNetService();
    // Demo mode: the channel buffers update exactly as they would with a
    // node on the network, but nothing is transmitted.
    await service.connect(const ArtNetSettings(demoMode: true));
    beats = StreamController<DateTime>.broadcast();
    player = ChasePlayer();
  });

  tearDown(() async {
    player.stop();
    await beats.close();
    await service.disconnect();
  });

  /// Every lamp's dimmer — all 255 on the flash, all 0 between beats.
  List<int> dimmers() => [for (final f in fixtures) service.getChannelValue(universe, f.startChannel)];

  test('a chase of two flash banks lights the rig on each beat and nowhere else', () async {
    var counter = 0;
    final scenes = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'scene-${counter++}');
    final banks = [
      for (var i = 0; i < 2; i++)
        Bank(id: 'bank-$i', name: 'Beat Flash ${i + 1}', sceneSlots: [scenes.first.id, scenes.last.id]),
    ];
    final steps = <int>[];

    unawaited(player.play(
      chase: Chase(
        id: 'c1',
        name: 'Two flash banks',
        steps: [for (final bank in banks) ChaseStep(bankId: bank.id)],
        beatSync: true,
      ),
      scenes: scenes,
      banks: banks,
      patchedFixtures: fixtures,
      universes: [universe],
      service: service,
      beatStream: beats.stream,
      beatRate: BeatRate.flash,
      flashLength: const Duration(milliseconds: 60),
      onStep: steps.add,
    ));

    // No beat yet: the rig waits in the dark instead of running away on the
    // step timer, which is exactly what a missing beat stream looked like.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(steps, [0]);
    expect(dimmers(), [0, 0, 0, 0]);

    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(steps, [0, 1], reason: 'the beat should have taken the chase to the lit step');
    expect(dimmers(), [255, 255, 255, 255], reason: 'all four lamps flash, not just one');

    // The flash is over well before the next beat, and what follows is the
    // *second* bank's dark scene — the chase moved on, not looped.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(steps, [0, 1, 2]);
    expect(dimmers(), [0, 0, 0, 0]);

    // Second beat: the second bank flashes too.
    beats.add(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(steps, [0, 1, 2, 3]);
    expect(dimmers(), [255, 255, 255, 255]);

    // And round it goes, back to the first bank.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(steps, [0, 1, 2, 3, 0]);
    expect(dimmers(), [0, 0, 0, 0]);
  });

  test('without a beat stream the same chase never waits — it runs on its own timers', () async {
    // The other half of the old bug: `beatSync: true` alone does nothing if
    // the caller doesn't hand the player a stream, so a screen that forgets
    // one silently degrades to timed steps instead of failing loudly.
    var counter = 0;
    final scenes = buildBeatFlashScenes(fixtures: fixtures, idGenerator: () => 'scene-${counter++}');
    final bank = Bank(id: 'bank-0', name: 'Beat Flash', sceneSlots: [scenes.first.id, scenes.last.id]);
    final steps = <int>[];

    unawaited(player.play(
      chase: Chase(
        id: 'c1',
        name: 'One flash bank',
        steps: [const ChaseStep(bankId: 'bank-0', hold: Duration(milliseconds: 30), fade: Duration.zero)],
        beatSync: true,
      ),
      scenes: scenes,
      banks: [bank],
      patchedFixtures: fixtures,
      universes: [universe],
      service: service,
      beatRate: BeatRate.flash,
      onStep: steps.add,
    ));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(steps.length, greaterThan(2), reason: 'no beat stream means the hold times drive it');
  });
}

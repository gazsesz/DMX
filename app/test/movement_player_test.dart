import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);

  const mover = FixtureProfile(
    id: 'mover',
    name: 'Mover',
    category: FixtureCategory.movingHead,
    channels: [
      FixtureChannel(offset: 0, function: ChannelFunction.pan),
      FixtureChannel(offset: 1, function: ChannelFunction.panFine),
      FixtureChannel(offset: 2, function: ChannelFunction.tilt),
      FixtureChannel(offset: 3, function: ChannelFunction.tiltFine),
      FixtureChannel(offset: 4, function: ChannelFunction.dimmer),
    ],
  );
  final fixtures = [
    const PatchedFixture(id: 'm1', label: 'M1', profile: mover, universeId: 'u1', startChannel: 0, layoutX: 0.3),
    const PatchedFixture(id: 'm2', label: 'M2', profile: mover, universeId: 'u1', startChannel: 10, layoutX: 0.7),
  ];

  late ArtNetService service;
  late ChasePlayer player;

  setUp(() async {
    service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    player = ChasePlayer(layerId: 'L1');
  });

  tearDown(() {
    player.dispose();
    service.disconnect();
  });

  int ch(int channel) => service.getChannelValue(universe, channel);
  PanTilt position(int start) => PanTilt.fromChannels(
    pan: ch(start),
    panFine: ch(start + 1),
    tilt: ch(start + 2),
    tiltFine: ch(start + 3),
  );

  Future<void> play(Chase chase, List<Bank> banks, {List<Bank> Function()? liveBanks}) => player.play(
    chase: chase,
    scenes: const [],
    banks: banks,
    patchedFixtures: fixtures,
    universes: const [universe],
    service: service,
    liveBanks: liveBanks,
  );

  Chase single(Bank bank, {Duration hold = Duration.zero, Duration fade = Duration.zero}) => Chase(
    id: 'c',
    name: 'c',
    steps: [ChaseStep(bankId: bank.id, hold: hold, fade: fade)],
  );

  const circle = MovementFx(periodSec: 1, sizePanDeg: 60, sizeTiltDeg: 40);
  final fxBank = Bank(id: 'fx', name: 'Circle', sceneSlots: const [], fx: circle);

  test('an FX bank moves the heads, 16-bit, and runs until stopped', () async {
    unawaited(play(single(fxBank), [fxBank]));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.isPlaying, isTrue);
    final seen = <PanTilt>{};
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      seen.add(position(0));
    }
    expect(seen.length, greaterThan(5), reason: 'the head keeps moving');
    expect(seen.any((p) => p.panFine != 0 || p.tiltFine != 0), isTrue, reason: 'fine channels are driven too');
    expect(ch(4), 0, reason: 'the dimmer is not touched');
    player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final stopped = position(0);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(position(0), stopped, reason: 'stop leaves the heads where they are');
  });

  test('an FX step with a hold ends and hands on to the next step', () async {
    final second = Bank(id: 'fx2', name: 'Sweep', sceneSlots: const [], fx: const MovementFx(shape: MovementShape.sweep));
    final chase = Chase(
      id: 'c',
      name: 'c',
      steps: const [
        ChaseStep(bankId: 'fx', hold: Duration(milliseconds: 150), fade: Duration.zero),
        ChaseStep(bankId: 'fx2', hold: Duration.zero, fade: Duration.zero),
      ],
    );
    final steps = <int>[];
    unawaited(player.play(
      chase: chase,
      scenes: const [],
      banks: [fxBank, second],
      patchedFixtures: fixtures,
      universes: const [universe],
      service: service,
      onStep: steps.add,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(steps, [0, 1]);
  });

  test('the path glides in from where the heads are instead of jumping', () async {
    // Park the head far from the path's first point.
    service.setChannel(universe, 0, 0, send: false);
    service.setChannel(universe, 2, 0, send: false);
    final bank = fxBank.copyWith(fx: circle.copyWith(periodSec: 60));
    unawaited(play(single(bank, fade: const Duration(seconds: 1)), [bank]));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final early = position(0);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    final late = position(0);
    expect(early.pan, lessThan(late.pan - 1000), reason: 'still on its way early on');
    expect(early.pan, lessThan(PanTilt.center.pan ~/ 2));
  });

  test('editing the bank while it runs changes the path live', () async {
    var banks = [fxBank];
    unawaited(play(single(fxBank), banks, liveBanks: () => banks));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    banks = [fxBank.copyWith(fx: circle.copyWith(shape: MovementShape.tiltSweep, sizeTiltDeg: 0, sizePanDeg: 0))];
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final a = position(0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(position(0), a, reason: 'zero size: it sits at the centre');
    expect(a.pan, closeTo(PanTilt.center.pan, 2));
  });

  test('a fixture limited by id leaves the others alone', () async {
    final bank = fxBank.copyWith(fx: circle.copyWith(fixtureIds: {'m2'}));
    service.setChannel(universe, 0, 7, send: false);
    unawaited(play(single(bank), [bank]));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(ch(0), 7);
    expect(position(10), isNot(PanTilt.center));
  });

  test('FX steps carry the phase on, unless the step asks for a restart', () async {
    Future<double> panDegAfterHandover({required bool restart}) async {
      final chase = Chase(
        id: 'c',
        name: 'c',
        steps: [
          const ChaseStep(bankId: 'fx', hold: Duration(milliseconds: 300), fade: Duration.zero),
          ChaseStep(bankId: 'fx', hold: Duration.zero, fade: Duration.zero, fxRestart: restart),
        ],
      );
      final local = ChasePlayer(layerId: 'L1');
      unawaited(local.play(
        chase: chase,
        scenes: const [],
        banks: [fxBank],
        patchedFixtures: fixtures,
        universes: const [universe],
        service: service,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 360));
      final degrees = (position(0).pan / PanTilt.max - 0.5) * 540;
      local.dispose();
      return degrees;
    }

    // One lap a second, circle: a fresh lap starts at the +pan extreme.
    expect(await panDegAfterHandover(restart: true), greaterThan(35));
    expect(await panDegAfterHandover(restart: false), lessThan(20));
  });
}

import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/movement_live_bar.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/control_dock_providers.dart';
import 'package:dmx_controller/state/movement_live_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MovementLive', () {
    test('size scales every size field, shift adds to the wave, both within range', () {
      const fx = MovementFx(sizePanDeg: 40, sizeTiltDeg: 20, sizeXM: 2, sizeYM: 1, phaseSpread: 0.4);
      final live = const MovementLive().copyWith(size: 1.5, shift: 0.3).applyTo(fx);
      expect(live.sizePanDeg, 60);
      expect(live.sizeTiltDeg, 30);
      expect(live.sizeXM, 3);
      expect(live.sizeYM, 1.5);
      expect(live.phaseSpread, closeTo(0.7, 1e-9));
      expect(const MovementLive().copyWith(shift: 1).applyTo(fx).phaseSpread, 1.0);
    });

    test('neutral changes nothing and the knobs clamp', () {
      const fx = MovementFx();
      expect(identical(MovementLive.neutral.applyTo(fx), fx), isTrue);
      final extreme = const MovementLive().copyWith(size: 9, speed: 99, shift: -3, smooth: 5);
      expect(extreme.size, 2);
      expect(extreme.speed, 4);
      expect(extreme.shift, 0);
      expect(extreme.smoothing, const Duration(milliseconds: 1500));
      expect(MovementLive.neutral.isNeutral, isTrue);
    });
  });

  group('player', () {
    const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);
    const mover = FixtureProfile(
      id: 'mover',
      name: 'Mover',
      category: FixtureCategory.movingHead,
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.pan),
        FixtureChannel(offset: 1, function: ChannelFunction.tilt),
      ],
    );
    const head = PatchedFixture(id: 'h', label: 'H', profile: mover, universeId: 'u1', startChannel: 0);
    late ArtNetService service;
    late ChasePlayer player;
    var live = MovementLive.neutral;

    setUp(() async {
      live = MovementLive.neutral;
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      player = ChasePlayer(layerId: 'L1');
    });

    tearDown(() {
      player.dispose();
      service.disconnect();
    });

    Future<void> run(MovementFx fx) {
      final bank = Bank(id: 'fx', name: 'Move', sceneSlots: const [], fx: fx);
      return player.play(
        chase: const Chase(
          id: 'c',
          name: 'c',
          steps: [ChaseStep(bankId: 'fx', hold: Duration.zero, fade: Duration.zero)],
        ),
        scenes: const [],
        banks: [bank],
        patchedFixtures: const [head],
        universes: const [universe],
        service: service,
        liveMovement: () => live,
      );
    }

    /// The widest the pan swings over [ms], as the DMX values it touched.
    Future<int> swing(int ms) async {
      var lo = 255;
      var hi = 0;
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final v = service.getChannelValue(universe, 0);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      return hi - lo;
    }

    const sweep = MovementFx(shape: MovementShape.panSweep, periodSec: 0.8, sizePanDeg: 60, sizeTiltDeg: 0);

    test('the size knob widens the swing live', () async {
      unawaited(run(sweep));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final normal = await swing(1000);
      live = live.copyWith(size: 0.25);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final small = await swing(1000);
      expect(small, lessThan(normal * 0.5));
      live = live.copyWith(size: 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final big = await swing(1000);
      expect(big, greaterThan(normal * 1.4));
    });

    test('the speed knob changes how fast the lap runs', () async {
      // A slow bank: in 400 ms it barely moves at x1, and covers the swing at x4.
      const slow = MovementFx(shape: MovementShape.panSweep, periodSec: 8, sizePanDeg: 60, sizeTiltDeg: 0);
      unawaited(run(slow));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final at1 = await swing(400);
      live = live.copyWith(speed: 4);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final at4 = await swing(1500);
      expect(at4, greaterThan(at1 + 10));
    });

    test('smooth makes the heads lag behind a sharp move', () async {
      const jumpy = MovementFx(shape: MovementShape.randomJump, periodSec: 1.6, sizePanDeg: 100, sizeTiltDeg: 0);
      unawaited(run(jumpy));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      Future<int> biggestStep() async {
        var last = service.getChannelValue(universe, 0);
        var biggest = 0;
        final end = DateTime.now().add(const Duration(milliseconds: 1800));
        while (DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          final v = service.getChannelValue(universe, 0);
          if ((v - last).abs() > biggest) biggest = (v - last).abs();
          last = v;
        }
        return biggest;
      }

      final hard = await biggestStep();
      live = live.copyWith(smooth: 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final soft = await biggestStep();
      expect(soft, lessThan(hard));
    });
  });

  group('the strip', () {
    Future<ProviderContainer> open(WidgetTester tester, {Size size = const Size(1000, 300)}) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MovementLiveBar())),
        ),
      ));
      return container;
    }

    testWidgets('dragging a knob sets it, double tap on its label and the reset button put it back', (tester) async {
      final container = await open(tester);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await tester.drag(find.byType(Slider).first, const Offset(600, 0));
      await tester.pump();
      expect(container.read(movementLiveProvider).size, 2.0);

      await tester.drag(find.byType(Slider).at(2), const Offset(600, 0));
      await tester.pump();
      expect(container.read(movementLiveProvider).shift, 1.0);

      await tester.tap(find.text('Size'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Size'));
      await tester.pump();
      expect(container.read(movementLiveProvider).size, 1.0, reason: 'double tap resets one knob');
      expect(container.read(movementLiveProvider).shift, 1.0);

      await tester.tap(find.byTooltip('Reset the Movement knobs'));
      await tester.pump();
      expect(container.read(movementLiveProvider).isNeutral, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('on a narrow screen the four knobs wrap into two rows', (tester) async {
      await open(tester, size: const Size(480, 300));
      expect(find.byType(Slider), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });

  test('the strip is on by default and its switch lives in the dock state', () async {
    SharedPreferences.setMockInitialValues({});
    expect(controlDockFromPrefs().movementBarVisible, isTrue);
    expect(controlDockFromPrefs(movementBarVisible: false).movementBarVisible, isFalse);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(controlDockProvider.notifier).toggleMovementBar();
    expect(container.read(controlDockProvider).movementBarVisible, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}

import 'dart:convert';

import 'package:dmx_controller/core/generator/program_generator.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/banks/program_generator_screen.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/stage_plan.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:dmx_controller/state/stage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
  PatchedFixture lamp(String id, {double x = 0.5, double y = 0.5}) =>
      PatchedFixture(id: id, label: id, profile: rgbPar, universeId: 'u1', startChannel: 0, layoutX: x, layoutY: y);

  // Patched C, A, B — but standing A, B, C left to right on the stage.
  final rig = [
    lamp('C', x: 0.9),
    lamp('A', x: 0.1),
    lamp('B', x: 0.5),
  ];
  List<String> ids(List<PatchedFixture> fs) => [for (final f in fs) f.id];

  group('orderFixtures', () {
    test('stage order follows the stage plan, both ways', () {
      expect(ids(orderFixtures(rig, FixtureOrder.stageLeftToRight)), ['A', 'B', 'C']);
      expect(ids(orderFixtures(rig, FixtureOrder.stageRightToLeft)), ['C', 'B', 'A']);
    });

    test('lamps never laid out keep their patch order', () {
      final unplaced = [lamp('C'), lamp('A'), lamp('B')];
      expect(ids(orderFixtures(unplaced, FixtureOrder.stageLeftToRight)), ['C', 'A', 'B']);
      expect(ids(orderFixtures(unplaced, FixtureOrder.stageRightToLeft)), ['C', 'A', 'B']);
    });

    test('lamps level on X go upstage first', () {
      final column = [lamp('front', x: 0.3, y: 0.9), lamp('back', x: 0.3, y: 0.1)];
      expect(ids(orderFixtures(column, FixtureOrder.stageLeftToRight)), ['back', 'front']);
    });

    test('custom order wins, lamps missing from it go last in stage order', () {
      expect(ids(orderFixtures(rig, FixtureOrder.custom, customOrder: ['A', 'C', 'B'])), ['A', 'C', 'B']);
      expect(ids(orderFixtures(rig, FixtureOrder.custom, customOrder: ['C'])), ['C', 'A', 'B']);
    });
  });

  test('the lamp order is saved with the project', () {
    final data = ProjectData(
      name: 'Club',
      settings: const ArtNetSettings(),
      universes: const [],
      customFixtureProfiles: const [],
      patchedFixtures: const [],
      scenes: const [],
      banks: const [],
      chases: const [],
      stagePlan: const StagePlan(fixtureOrder: FixtureOrder.custom, customFixtureOrder: ['C', 'A', 'B']),
    );
    final back = ProjectData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>, builtIns: const []);
    expect(back.stagePlan.fixtureOrder, FixtureOrder.custom);
    expect(back.stagePlan.customFixtureOrder, ['C', 'A', 'B']);
    // Older project files have no lamp order: stage left to right.
    expect(StagePlan.fromJson(const {'widthM': 8, 'depthM': 6}).fixtureOrder, FixtureOrder.stageLeftToRight);
  });

  group('Program generator screen', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => null,
      );
      SharedPreferences.setMockInitialValues({});
    });

    Future<ProviderContainer> open(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(patchedFixturesProvider.notifier).loadAll(rig);
      await tester.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProgramGeneratorScreen()),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return container;
    }

    /// The comet head (brightest lamp) of each generated Running Light scene.
    List<String> litPerScene(ProviderContainer container) {
      final bank = container.read(banksProvider).last;
      final scenes = {for (final s in container.read(scenesProvider)) s.id: s};
      return [
        for (final id in bank.sceneSlots.whereType<String>())
          _litLamp(scenes[id]!),
      ];
    }

    Future<void> generateRunningLight(WidgetTester tester) async {
      await tester.tap(find.text('Running Light'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
    }

    testWidgets('a running light walks the stage left to right by default', (tester) async {
      final container = await open(tester);
      await generateRunningLight(tester);
      expect(litPerScene(container).take(3), ['A', 'B', 'C']);
    });

    testWidgets('stage right to left runs the other way and lands in the project', (tester) async {
      final container = await open(tester);
      await tester.tap(find.byKey(const ValueKey('order-stageRightToLeft')));
      await tester.pump();
      expect(container.read(stagePlanProvider).fixtureOrder, FixtureOrder.stageRightToLeft);
      await generateRunningLight(tester);
      expect(litPerScene(container).take(3), ['C', 'B', 'A']);
    });

    testWidgets('custom order starts from the stage order and can be dragged', (tester) async {
      final container = await open(tester);
      await tester.tap(find.byKey(const ValueKey('order-custom')));
      await tester.pump();
      expect(container.read(stagePlanProvider).customFixtureOrder, ['A', 'B', 'C']);
      // Drag C (last) to the top.
      final handle = find.descendant(
        of: find.byKey(const ValueKey('ordered-C')),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(stagePlanProvider).customFixtureOrder.take(3), ['C', 'A', 'B']);
      await generateRunningLight(tester);
      expect(litPerScene(container).take(3), ['C', 'A', 'B']);
      expect(tester.takeException(), isNull);
    });
  });
}

String _litLamp(Scene scene) {
  int level(Map<int, int> v) => [1, 2, 3].fold(0, (sum, ch) => sum + (v[ch] ?? 0)) * (v[0] ?? 255);
  final sorted = scene.fixtureValues.entries.toList()..sort((a, b) => level(b.value).compareTo(level(a.value)));
  return sorted.first.key;
}

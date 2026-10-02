import 'package:dmx_controller/core/positions/aim.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/pan_tilt_pad.dart';
import 'package:dmx_controller/features/scenes/scene_editor_screen.dart';
import 'package:dmx_controller/core/widgets/wheel_looks.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/builtin_fixtures.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/group_position.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The built-in 14-channel beam: pan, tilt, dimmer, strobe, colour wheel,
/// gobo, gobo rotation, zoom, focus, prism, frost, Reset (generic), speed,
/// Function (generic).
final _beam = builtInFixtureProfiles.firstWhere((p) => p.id == 'builtin-moving-head-beam');

PatchedFixture _head(String id, double x) => PatchedFixture(
  id: id,
  label: id.toUpperCase(),
  profile: _beam,
  universeId: 'u1',
  startChannel: 0,
  layoutX: x,
  layoutY: 0.1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> open(WidgetTester tester, List<PatchedFixture> heads, Scene scene) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(patchedFixturesProvider.notifier).loadAll(heads);
    container.read(scenesProvider.notifier).loadAll([scene]);
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: SceneEditorScreen(existing: scene)),
    ));
    await tester.pump();
    return container;
  }

  Future<Scene> save(WidgetTester tester, ProviderContainer container) async {
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    return container.read(scenesProvider).single;
  }

  testWidgets('Reset and Function keep their own values instead of sharing one', (tester) async {
    const scene = Scene(
      id: 's',
      name: 'Beam',
      fixtureValues: {
        'a': {0: 100, 1: 90, 2: 255, 9: 40, 10: 50, 11: 7, 12: 60, 13: 200},
      },
    );
    final container = await open(tester, [_head('a', 0.5)], scene);
    final saved = await save(tester, container);
    final values = saved.fixtureValues['a']!;
    expect(values[9], 40, reason: 'prism');
    expect(values[10], 50, reason: 'frost');
    expect(values[11], 7, reason: 'reset');
    expect(values[12], 60, reason: 'pan/tilt speed');
    expect(values[13], 200, reason: 'function');
  });

  testWidgets('a fanned group reopens on its shared position and saves every head fanned', (tester) async {
    final base = degreesToPanTilt(0, 30, panRangeDeg: 540, tiltRangeDeg: 270);
    final scene = Scene(
      id: 's',
      name: 'Fan',
      fixtureValues: const {
        'a': {0: 1, 1: 1},
        'b': {0: 1, 1: 1},
      },
      fixtureGroups: const [
        ['a', 'b'],
      ],
      groupPositions: [GroupPosition(fanPanDeg: 20, base: base)],
    );
    final container = await open(tester, [_head('a', 0.2), _head('b', 0.8)], scene);
    expect(find.text('Position'), findsWidgets);

    final saved = await save(tester, container);
    // ±10° either side of the base on a 540° head, 8-bit coarse channel.
    final expectedA = degreesToPanTilt(-10, 30, panRangeDeg: 540, tiltRangeDeg: 270);
    final expectedB = degreesToPanTilt(10, 30, panRangeDeg: 540, tiltRangeDeg: 270);
    expect(saved.fixtureValues['a']![0], expectedA.panCoarse);
    expect(saved.fixtureValues['b']![0], expectedB.panCoarse);
    expect(saved.fixtureValues['a']![1], base.tiltCoarse);
    expect(saved.groupPositions!.single!.fanPanDeg, 20);
    expect(saved.groupPositions!.single!.base, base);
  });

  testWidgets('touching the pad moves the whole group there', (tester) async {
    const scene = Scene(
      id: 's',
      name: 'Pad',
      fixtureValues: {
        'a': {0: 128, 1: 128},
        'b': {0: 128, 1: 128},
      },
      fixtureGroups: [
        ['a', 'b'],
      ],
    );
    final container = await open(tester, [_head('a', 0.2), _head('b', 0.8)], scene);
    final pad = find.byType(PanTiltPad);
    expect(pad, findsOneWidget);
    final rect = tester.getRect(pad);
    await tester.dragFrom(rect.topLeft + Offset(rect.width * 0.25, rect.height * 0.75), const Offset(0.5, 0));
    await tester.pumpAndSettle();

    final saved = await save(tester, container);
    for (final id in ['a', 'b']) {
      expect(saved.fixtureValues[id]![0], closeTo(64, 1), reason: 'pan of $id');
      expect(saved.fixtureValues[id]![1], closeTo(192, 1), reason: 'tilt of $id');
    }
    // A single shared position needs nothing extra saved.
    expect(saved.groupPositions?.single, isNull);
  });

  testWidgets('a plain RGB group keeps the original one-screen card', (tester) async {
    final par = builtInFixtureProfiles.firstWhere((p) => p.id == 'builtin-rgb-par');
    const scene = Scene(id: 's', name: 'Par', fixtureValues: {'p': {0: 255, 1: 255, 2: 0, 3: 0}});
    await open(
      tester,
      [PatchedFixture(id: 'p', label: 'PAR', profile: par, universeId: 'u1', startChannel: 0)],
      scene,
    );
    expect(find.byType(PanTiltPad), findsNothing);
    expect(find.text('Channels'), findsNothing);
  });

  testWidgets('Duplicate saves what is on screen as a new scene and leaves the original alone', (tester) async {
    final scene = Scene(
      id: 's',
      name: 'Chorus',
      fixtureValues: const {
        'a': {0: 1, 1: 1},
        'b': {0: 1, 1: 1},
      },
      fixtureGroups: const [
        ['a', 'b'],
      ],
      groupPositions: [GroupPosition(fanPanDeg: 20, base: PanTilt.center)],
    );
    final container = await open(tester, [_head('a', 0.2), _head('b', 0.8)], scene);
    await tester.tap(find.byTooltip('Duplicate'));
    await tester.pumpAndSettle();

    final scenes = container.read(scenesProvider);
    expect(scenes, hasLength(2));
    expect(scenes.first.fixtureValues, scene.fixtureValues, reason: 'the original is unchanged');
    final copy = scenes.last;
    expect(copy.name, 'Chorus Copy');
    expect(copy.fixtureGroups, scene.fixtureGroups);
    expect(copy.groupPositions!.single!.fanPanDeg, 20);
    expect(copy.fixtureValues['a']![0], isNot(copy.fixtureValues['b']![0]), reason: 'still fanned');
    // The editor now shows the copy.
    expect(find.text('Chorus Copy'), findsOneWidget);
  });

  group('Duplicate and banks', () {
    const scene = Scene(id: 's', name: 'Chorus', fixtureValues: {'a': {0: 1, 1: 1}});

    Future<ProviderContainer> openFrom(WidgetTester tester, {String? bankId, int? slot}) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(patchedFixturesProvider.notifier).loadAll([_head('a', 0.5)]);
      container.read(scenesProvider.notifier).loadAll([scene]);
      container.read(banksProvider.notifier).loadAll([
        const Bank(id: 'b', name: 'Verse', sceneSlots: ['x', 's', 'y', null, null]),
      ]);
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SceneEditorScreen(existing: scene, fromBankId: bankId, fromSlot: slot),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('Duplicate'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('opened from a bank, the copy goes into it right after the original', (tester) async {
      final container = await openFrom(tester, bankId: 'b', slot: 1);
      final copy = container.read(scenesProvider).last;
      expect(container.read(banksProvider).single.sceneSlots, ['x', 's', 'y', copy.id, null]);
      expect(find.textContaining('Added to Verse, slot 4'), findsOneWidget);

      // Duplicating the copy lines the next one up after it.
      await tester.tap(find.byTooltip('Duplicate'));
      await tester.pumpAndSettle();
      final second = container.read(scenesProvider).last;
      expect(container.read(banksProvider).single.sceneSlots, ['x', 's', 'y', copy.id, second.id]);
    });

    testWidgets('opened from anywhere else, the copy is left out of every bank', (tester) async {
      final container = await openFrom(tester);
      expect(container.read(scenesProvider), hasLength(2));
      expect(container.read(banksProvider).single.sceneSlots, ['x', 's', 'y', null, null]);
    });
  });

  test('placeAfter wraps round to the start, then grows a full bank', () {
    final notifier = BanksNotifier()
      ..loadAll([
        const Bank(id: 'b', name: 'B', sceneSlots: [null, 'a', 'b']),
      ]);
    expect(notifier.placeAfter('b', 1, 'c'), 0);
    expect(notifier.placeAfter('b', 1, 'd'), 3);
    expect(notifier.state.single.sceneSlots, ['c', 'a', 'b', 'd']);
    expect(notifier.placeAfter('gone', 0, 'e'), isNull);
  });

  testWidgets('a colour channel imported as generic gets swatches', (tester) async {
    final imported = FixtureProfile.fromJson({
      'id': 'zq',
      'name': 'ZQ02021 Beam Pro',
      'category': 'movingHead',
      'channels': [
        {'offset': 0, 'function': 'pan'},
        {'offset': 1, 'function': 'tilt'},
        {'offset': 2, 'function': 'pan', 'customLabel': 'Pan/Tilt speed'},
        {
          'offset': 3,
          'function': 'generic',
          'customLabel': 'Color',
          'capabilities': [
            {'min': 0, 'max': 15, 'label': 'no function', 'kind': 'slot'},
            {'min': 16, 'max': 31, 'label': 'Red', 'kind': 'slot'},
            {'min': 32, 'max': 47, 'label': 'Light Blue', 'kind': 'slot'},
            {'min': 128, 'max': 255, 'label': 'Automatic Change Slow to Fast', 'kind': 'range'},
          ],
        },
      ],
    });
    expect(imported.channels[2].function, ChannelFunction.panTiltSpeed);
    expect(imported.channels[3].function, ChannelFunction.colorWheel);

    const scene = Scene(id: 's', name: 'Zq', fixtureValues: {'z': {0: 128, 1: 128, 3: 20}});
    final container = await open(
      tester,
      [PatchedFixture(id: 'z', label: 'ZQ', profile: imported, universeId: 'u1', startChannel: 0)],
      scene,
    );
    await tester.tap(find.text('Color').first);
    await tester.pumpAndSettle();
    expect(find.byType(WheelSwatch), findsNWidgets(3));
    // Picking a swatch sets the wheel to that slot.
    await tester.tap(find.byType(WheelSwatch).at(2));
    await tester.pumpAndSettle();
    final saved = await save(tester, container);
    expect(saved.fixtureValues['z']![3], (32 + 47) ~/ 2);
  });

  test('PanTilt centre is what an untouched mover group saves', () {
    expect(PanTilt.center.panCoarse, 128);
  });
}

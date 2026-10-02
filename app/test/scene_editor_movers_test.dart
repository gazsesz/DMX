import 'package:dmx_controller/core/positions/aim.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/pan_tilt_pad.dart';
import 'package:dmx_controller/features/scenes/scene_editor_screen.dart';
import 'package:dmx_controller/models/builtin_fixtures.dart';
import 'package:dmx_controller/models/group_position.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
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

  test('PanTilt centre is what an untouched mover group saves', () {
    expect(PanTilt.center.panCoarse, 128);
  });
}

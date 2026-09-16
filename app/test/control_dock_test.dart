import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/control_dock.dart';
import 'package:dmx_controller/core/widgets/control_panel.dart';
import 'package:dmx_controller/models/control_dock_prefs.dart';
import 'package:dmx_controller/state/control_dock_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ControlDockPosition position, {List<Override> overrides = const []}) {
  // Mirrors how AppShell docks it: bottom takes the full width under the
  // content, right takes the full height beside it.
  final dock = ControlDock(position: position);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: position == ControlDockPosition.bottom
            ? Column(children: [const Expanded(child: SizedBox.expand()), dock])
            : Row(children: [const Expanded(child: SizedBox.expand()), dock]),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The open panel arms beat sync over a platform channel; there is no
    // plugin host in a widget test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
  });

  testWidgets('renders docked at the bottom with nothing playing', (tester) async {
    await tester.pumpWidget(_host(ControlDockPosition.bottom));
    expect(tester.takeException(), isNull);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Blackout'), findsOneWidget);
    expect(find.text('Beat'), findsOneWidget);
  });

  testWidgets('renders docked on the right', (tester) async {
    await tester.pumpWidget(_host(ControlDockPosition.right));
    expect(tester.takeException(), isNull);
    expect(find.text('Blackout'), findsOneWidget);
  });

  testWidgets('live stage strip renders along the bottom', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [Expanded(child: SizedBox.expand()), LiveStageDock()]),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveStageDock), findsOneWidget);
  });

  testWidgets('shows what is playing instead of Idle', (tester) async {
    await tester.pumpWidget(
      _host(
        ControlDockPosition.bottom,
        overrides: [
          nowPlayingProvider.overrideWith(
            (ref) => const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash'),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Front Wash'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });

  testWidgets('the panel toggle sits among the dock buttons, not off on its own', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [Expanded(child: SizedBox.expand()), ControlDock(position: ControlDockPosition.bottom)],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tempo'), findsOneWidget);
    // Within the strip's own bounds — the old chevron tab hung off the
    // dock's edge at the far side of the screen.
    final dock = tester.getRect(find.byType(ControlDock));
    expect(dock.contains(tester.getCenter(find.text('Tempo'))), isTrue);

    await tester.tap(find.text('Tempo'));
    await tester.pump();
    expect(container.read(controlDockProvider).expanded, isTrue);
  });

  testWidgets('the open dock keeps the basic controls, stacked down a rail', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(controlDockProvider.notifier).toggleExpanded();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 600, height: 460, child: ExpandedControlDock()),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The tempo panel, and the strip's controls beside it.
    expect(find.byType(ControlPanel), findsOneWidget);
    expect(find.text('Blackout'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    // Stacked, not in a row: each button sits below the previous one.
    final blackout = tester.getCenter(find.text('Blackout'));
    final master = tester.getCenter(find.text('Master'));
    expect(blackout.dy, greaterThan(master.dy));
    expect((blackout.dx - master.dx).abs(), lessThan(20));

    // And a way out that says what it closes.
    expect(find.text('Control dock'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(container.read(controlDockProvider).expanded, isFalse);
  });

  // A tablet stood upright is 600dp wide, which the strip used to solve by
  // scrolling sideways — leaving Tempo off the screen entirely and half of
  // Blackout with it. It has to wrap instead.
  testWidgets('the strip wraps rather than running off an upright tablet', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        ControlDockPosition.bottom,
        overrides: [
          nowPlayingProvider.overrideWith(
            (ref) => const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash'),
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final label in ['Front Wash', 'Stop', 'Beat', 'AutoFade', 'Master', 'Blackout', 'Tempo']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$label runs off the left');
      expect(rect.right, lessThanOrEqualTo(screen), reason: '$label runs off the right');
    }
  });

  // 360dp can't hold all of it on two rows, so the strip gives up auto
  // fade — which is why the panel carries that switch too.
  testWidgets('a 360dp phone keeps the controls that matter', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        ControlDockPosition.bottom,
        overrides: [
          nowPlayingProvider.overrideWith(
            (ref) => const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash'),
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Blackout'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Master'), findsOneWidget);
    // Auto fade is the one given up — a switch you set once, and the panel
    // has it.
    expect(find.text('AutoFade'), findsNothing);
  });

  // The rail eats ~80px of the panel's width, and the narrowest phone this
  // has to run on is 360dp wide — so the tempo controls beside it get about
  // 260. If that overflows, the panel is unusable on that device.
  testWidgets('the open dock fits a 360dp phone', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 344, height: 560, child: ExpandedControlDock()),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Blackout'), findsOneWidget);
  });
}

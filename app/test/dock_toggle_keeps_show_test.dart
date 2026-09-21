import 'dart:io';

import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/dashboard/dashboard_screen.dart';
import 'package:dmx_controller/features/shell/app_shell.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/control_dock_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opening the dock's panel and closing it again must leave the show alone.
///
/// It didn't: the shell swapped its whole layout around the tab content, so
/// every screen was torn down and rebuilt — which threw away what each one
/// remembered about the running show (which slot is lit, which zone a smart
/// program is in), and left the Dashboard looking idle while the rig was
/// still going.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('dmx_dock').path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => {
        'appName': 'DMX Controller',
        'packageName': 'com.gazsesz.dmx_controller',
        'version': '1.10.1',
        'buildNumber': '17',
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opening and closing the panel leaves the running show alone', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );
    await tester.pump();

    // Something is playing: one scene, held long enough to still be running
    // when the test is done with it.
    final player = container.read(playbackControllerProvider);
    player.play(
      chase: const Chase(
        id: 'c1',
        name: 'Verse',
        steps: [ChaseStep(sceneId: 's1', hold: Duration(seconds: 30))],
      ),
      scenes: const [Scene(id: 's1', name: 'Look', fixtureValues: {})],
      banks: const [],
      patchedFixtures: const [],
      universes: const [],
      service: container.read(artNetServiceProvider),
      onStep: (_) {},
    );
    container.read(nowPlayingProvider.notifier).state = const NowPlaying(
      id: 'c1',
      kind: PlaybackKind.chase,
      name: 'Verse',
    );
    await tester.pump();
    expect(player.isPlaying, isTrue, reason: 'nothing is playing to begin with');

    final dashboardBefore = tester.state(find.byType(DashboardScreen));

    // Open the panel, then close it again — the Tempo button, then Close.
    await tester.tap(find.text('Tempo'));
    await tester.pump();
    expect(container.read(controlDockProvider).expanded, isTrue);
    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(container.read(controlDockProvider).expanded, isFalse);

    expect(player.isPlaying, isTrue, reason: 'the panel stopped playback');
    expect(
      tester.state(find.byType(DashboardScreen)),
      same(dashboardBefore),
      reason: 'the tab content was rebuilt from scratch, losing what it knew about the show',
    );

    // Leave nothing running: the player's step loop is a real timer, and
    // the test binding fails a test that walks away from one.
    player.stop();
    await tester.pump(const Duration(milliseconds: 50));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/shell/app_shell.dart';
import 'package:dmx_controller/state/control_dock_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the screenshots in `design/screenshots/`.
///
/// Not part of the suite: it lives in `tool/` so `flutter test` doesn't pick
/// it up (a golden of the whole shell would fail on any machine whose font
/// rasterisation differs). Refresh them with:
///
///     flutter test tool/screenshots_test.dart --update-goldens
void main() {
  setUp(() {
    // Every tab is built up front by the shell's IndexedStack, so a still
    // of the Dashboard also brings up Files (documents directory), Setup
    // (package version) and the beat detector (the recorder). None of them
    // has a plugin host in a widget test.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('dmx_shot').path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => {
        'appName': 'DMX Controller',
        'packageName': 'com.example.dmx_controller',
        'version': '1.10.0',
        'buildNumber': '16',
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    // This file is a test; it just lives in tool/ so the suite doesn't pick
    // it up, which is why the analyzer doesn't believe the mock belongs.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    // Widget tests draw text in a placeholder font — the real Manrope, IBM
    // Plex Mono and MaterialIcons have to be loaded by hand or every label
    // in the shot comes out as a row of boxes.
    final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final family = entry['family'] as String;
      final assets = (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>();
      // Anything the theme doesn't name a family for falls back to Roboto,
      // which isn't in the bundle — on a real device the platform provides
      // it, in a test those labels come out as solid blocks. Manrope
      // answers to the name here so the shot matches the device.
      for (final name in [family, if (family == appFontFamily) 'Roboto']) {
        final loader = FontLoader(name);
        for (final font in assets) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
    }
  });

  Future<void> shoot(
    WidgetTester tester, {
    required Size size,
    required String name,
    bool expanded = true,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        nowPlayingProvider.overrideWith(
          (ref) => const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Verse Wash'),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (expanded) container.read(controlDockProvider.notifier).toggleExpanded();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const AppShell(),
        ),
      ),
    );
    // Something on the Dashboard animates continuously, so settle would
    // never return — a couple of frames is all a still needs.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 260));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../design/screenshots/$name.png'));
  }

  testWidgets('the open control dock on a tablet', (tester) async {
    await shoot(tester, size: const Size(1024, 680), name: 'control-dock-open-tablet');
  });

  testWidgets('the open control dock on a phone', (tester) async {
    await shoot(tester, size: const Size(392, 760), name: 'control-dock-open-phone');
  });

  // The Tab S6 Lite stood on its end: 600x1000 logical, i.e. below the
  // tablet breakpoint, so it gets the phone layout on a screen that isn't
  // one.
  testWidgets('the dock on a tablet held upright', (tester) async {
    await shoot(tester, size: const Size(600, 1000), name: 'control-dock-open-tablet-portrait');
  });

  testWidgets('the closed dock on a tablet held upright', (tester) async {
    await shoot(
      tester,
      size: const Size(600, 1000),
      name: 'control-dock-closed-tablet-portrait',
      expanded: false,
    );
  });

  testWidgets('the closed dock strip, with the panel button on the end of it', (tester) async {
    await shoot(
      tester,
      size: const Size(1024, 680),
      name: 'control-dock-closed-tablet',
      expanded: false,
    );
  });
}


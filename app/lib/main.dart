import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'models/artnet_settings.dart';
import 'state/artnet_providers.dart';
import 'state/control_dock_providers.dart';
import 'state/dashboard_prefs_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This app runs at venues on the lighting node's own isolated Wi-Fi, with
  // no internet — never let google_fonts try to fetch a font over the
  // network; just fall back to the platform default instead of throwing.
  GoogleFonts.config.allowRuntimeFetching = false;

  // This is a live lighting console, not something you glance at — the
  // screen must never sleep mid-show. No-op on platforms without a real
  // wakelock concept (desktop just ignores it).
  unawaited(WakelockPlus.enable());

  // Load the persisted connection settings *before* the first frame, not
  // asynchronously after — every tab (Settings included) is built up front
  // by AppShell's IndexedStack, so a Settings screen built on that very
  // first frame would otherwise snapshot the constructor default into its
  // text fields and never notice the real value loading moments later.
  final prefs = await SharedPreferences.getInstance();
  const fallback = ArtNetSettings();
  final initialSettings = ArtNetSettings(
    deviceName: prefs.getString('artnet.deviceName') ?? fallback.deviceName,
    host: prefs.getString('artnet.host') ?? fallback.host,
    port: prefs.getInt('artnet.port') ?? fallback.port,
    broadcast: prefs.getBool('artnet.broadcast') ?? fallback.broadcast,
    demoMode: prefs.getBool('artnet.demoMode') ?? fallback.demoMode,
  );

  final initialDashboardPrefs = dashboardPrefsFromStrings(
    layout: prefs.getString(prefDashboardLayout),
    boxSize: prefs.getString(prefDashboardBoxSize),
  );

  final initialDock = controlDockFromPrefs(
    visible: prefs.getBool(prefDockVisible),
    position: prefs.getString(prefDockPosition),
    stageVisible: prefs.getBool(prefStageVisible),
  );

  runApp(
    ProviderScope(
      overrides: [
        artNetSettingsProvider.overrideWith((ref) => ArtNetSettingsNotifier(initialSettings)),
        dashboardPrefsProvider.overrideWith((ref) => DashboardPrefsNotifier(initialDashboardPrefs)),
        controlDockProvider.overrideWith((ref) => ControlDockNotifier(initialDock)),
      ],
      child: const DmxControllerApp(),
    ),
  );
}

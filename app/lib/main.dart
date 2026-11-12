import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'core/audio/beat_detector.dart';
import 'core/midi/midi_control_service.dart';
import 'models/artnet_settings.dart';
import 'models/output_protocol.dart';
import 'state/artnet_providers.dart';
import 'state/audio_providers.dart';
import 'state/control_dock_providers.dart';
import 'state/dashboard_prefs_providers.dart';
import 'state/locale_providers.dart';
import 'state/midi_control_providers.dart';
import 'state/remote_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This is a live lighting console, not something you glance at — the
  // screen must never sleep mid-show. No-op on platforms without a real
  // wakelock concept (desktop just ignores it).
  unawaited(WakelockPlus.enable());

  // Bluetooth MIDI controllers. The transport has to be attached before
  // anything subscribes to incoming MIDI: a stream read earlier never picks
  // the BLE side up. Nothing touches the radio (or asks for permission)
  // until a scan is started from Setup.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      MidiCommand().configureBleTransport(UniversalBleMidiTransport());
      MidiControlService.markBluetoothConfigured();
    } catch (_) {
      // No BLE on this build/device: USB controllers still work.
    }
  }

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
    protocol: OutputProtocol.fromName(prefs.getString(prefOutputProtocol)),
    sacnPriority: prefs.getInt(prefSacnPriority) ?? fallback.sacnPriority,
    demoMode: prefs.getBool('artnet.demoMode') ?? fallback.demoMode,
  );

  final initialDashboardPrefs = dashboardPrefsFromStrings(
    layout: prefs.getString(prefDashboardLayout),
    boxSize: prefs.getString(prefDashboardBoxSize),
  );

  final initialRemote = remoteControlFromPrefs(
    enabled: prefs.getBool(prefRemoteEnabled),
    port: prefs.getInt(prefRemotePort),
  );

  final initialDock = controlDockFromPrefs(
    expanded: prefs.getBool(prefDockExpanded),
    position: prefs.getString(prefDockPosition),
    stageVisible: prefs.getBool(prefStageVisible),
    movementBarVisible: prefs.getBool(prefMovementBarVisible),
    colorBarVisible: prefs.getBool(prefColorBarVisible),
  );

  final initialBeatSource = beatSourcePrefsFromStrings(
    kind: prefs.getString(prefBeatSourceKind),
    midiDeviceId: prefs.getString(prefBeatSourceMidiDeviceId),
    midiDeviceName: prefs.getString(prefBeatSourceMidiDeviceName),
  );

  runApp(
    ProviderScope(
      overrides: [
        artNetSettingsProvider.overrideWith((ref) => ArtNetSettingsNotifier(initialSettings)),
        dashboardPrefsProvider.overrideWith((ref) => DashboardPrefsNotifier(initialDashboardPrefs)),
        controlDockProvider.overrideWith((ref) => ControlDockNotifier(initialDock)),
        remoteControlProvider.overrideWith((ref) => RemoteControlNotifier(initialRemote)),
        beatSourcePrefsProvider.overrideWith((ref) => BeatSourcePrefsNotifier(initialBeatSource)),
        appLanguageProvider.overrideWith(
          (ref) => AppLanguageNotifier(AppLanguage.fromName(prefs.getString(prefAppLanguage))),
        ),
        initialMidiControlDevicesProvider.overrideWithValue(
          midiControlDevicesFromPrefs(prefs.getStringList(prefMidiControlDevices)),
        ),
        initialSilenceFloorProvider.overrideWithValue(
          prefs.getDouble(prefBeatSilenceFloor) ?? BeatDetectorService.silenceFloorOff,
        ),
      ],
      child: const DmxControllerApp(),
    ),
  );
}

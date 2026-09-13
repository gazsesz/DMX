import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to the Android foreground service that keeps the app's process —
/// and therefore its remote-control HTTP server — alive while the screen
/// is off.
///
/// The endpoint itself is pure Dart and binds its socket happily; what Dart
/// cannot do is stop Android freezing the process a minute after the screen
/// goes off, which is exactly when a trigger fired from a watch needs to
/// land. Hence a real foreground service with a persistent notification:
/// there is no other supported way to stay reachable.
///
/// Every call is a no-op off Android, so callers don't have to guard.
class BackgroundService {
  static const _channel = MethodChannel('com.gazsesz.dmx_controller/background');

  static bool get isSupported => Platform.isAndroid;

  /// Starts the service. Safe to call when it's already running.
  static Future<void> start() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('start');
    } on PlatformException catch (_) {
      // Nothing the user can do about it and nothing worth interrupting a
      // show for — the endpoint still works while the app is in front.
    } on MissingPluginException catch (_) {
      // Older build of the app shell, or a unit test.
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (_) {
      // As above.
    } on MissingPluginException catch (_) {}
  }

  /// True when Android is still allowed to doze this app.
  ///
  /// The foreground service covers the normal case, but aggressive
  /// manufacturer battery managers (Huawei's especially) will still kill a
  /// backgrounded app unless it's exempted — so Settings shows this and
  /// offers the system dialog.
  static Future<bool> isBatteryOptimized() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimized') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "ignore battery optimisations" prompt. Returns false
  /// if the device has no such screen; a true only means the dialog opened,
  /// never that the user agreed — re-read [isBatteryOptimized] afterwards.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/remote/remote_control_server.dart';
import 'provider_reader.dart';

const prefRemoteEnabled = 'remote.enabled';
const prefRemotePort = 'remote.port';
const defaultRemotePort = 8080;

class RemoteControlState {
  final bool enabled;
  final int port;

  const RemoteControlState({this.enabled = false, this.port = defaultRemotePort});

  RemoteControlState copyWith({bool? enabled, int? port}) =>
      RemoteControlState(enabled: enabled ?? this.enabled, port: port ?? this.port);
}

/// The remote-control endpoint's on/off state and port. Persisted so a show
/// laptop or a watch macro keeps working after the tablet restarts.
class RemoteControlNotifier extends StateNotifier<RemoteControlState> {
  RemoteControlNotifier(super.initial);

  void set(RemoteControlState next) {
    state = next;
    _persist(next);
  }

  Future<void> _persist(RemoteControlState prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefRemoteEnabled, prefs.enabled);
    await sp.setInt(prefRemotePort, prefs.port);
  }
}

final remoteControlProvider = StateNotifierProvider<RemoteControlNotifier, RemoteControlState>((ref) {
  return RemoteControlNotifier(const RemoteControlState());
});

/// The server itself. It reads providers through `ref.read`, which is the
/// same entry point the Dashboard's tiles use, so a remote trigger and a tap
/// run identical code.
final remoteControlServerProvider = Provider<RemoteControlServer>((ref) {
  final server = RemoteControlServer(ref.read);
  ref.onDispose(server.stop);
  return server;
});

RemoteControlState remoteControlFromPrefs({bool? enabled, int? port}) {
  return RemoteControlState(enabled: enabled ?? false, port: port ?? defaultRemotePort);
}

/// Brings the server in line with the current setting — called at startup and
/// whenever the switch or port changes.
Future<void> applyRemoteControlSetting(ReadProvider read) async {
  final settings = read(remoteControlProvider);
  final server = read(remoteControlServerProvider);
  if (!settings.enabled) {
    await server.stop();
    return;
  }
  await server.start(settings.port);
}

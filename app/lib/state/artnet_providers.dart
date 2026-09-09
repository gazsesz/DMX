import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/artnet/artnet_service.dart';
import '../models/artnet_settings.dart';
import '../models/universe_config.dart';

/// The single shared UDP sender for the whole app.
final artNetServiceProvider = Provider<ArtNetService>((ref) {
  final service = ArtNetService();
  ref.onDispose(() => service.disconnect());
  return service;
});

final artNetSettingsProvider =
    StateNotifierProvider<ArtNetSettingsNotifier, ArtNetSettings>((ref) {
      return ArtNetSettingsNotifier(const ArtNetSettings());
    });

const _prefDeviceName = 'artnet.deviceName';
const _prefHost = 'artnet.host';
const _prefPort = 'artnet.port';
const _prefBroadcast = 'artnet.broadcast';

/// Connection settings the user configures once for their venue's node —
/// unlike scenes/banks/chases (deliberately saved/loaded as named show
/// files), these persist automatically across app restarts, the same way a
/// real console remembers its network config without a separate "save".
///
/// The *loading* half of that happens in `main()`, before the first frame —
/// see there for why: every tab (Settings included) is built up front by
/// AppShell's IndexedStack, so loading asynchronously here would race a
/// Settings screen that already snapshotted the constructor default into
/// its text fields on that very first frame.
class ArtNetSettingsNotifier extends StateNotifier<ArtNetSettings> {
  ArtNetSettingsNotifier(super.initial);

  void update(ArtNetSettings Function(ArtNetSettings current) updater) {
    state = updater(state);
    _persist(state);
  }

  Future<void> _persist(ArtNetSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDeviceName, settings.deviceName);
    await prefs.setString(_prefHost, settings.host);
    await prefs.setInt(_prefPort, settings.port);
    await prefs.setBool(_prefBroadcast, settings.broadcast);
  }
}

final universesProvider =
    StateNotifierProvider<UniversesNotifier, List<UniverseConfig>>((ref) {
      return UniversesNotifier();
    });

class UniversesNotifier extends StateNotifier<List<UniverseConfig>> {
  UniversesNotifier() : super(const [UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0)]);

  void addUniverse() {
    final nextIndex = state.length;
    state = [
      ...state,
      UniverseConfig(
        id: 'u-${DateTime.now().microsecondsSinceEpoch}',
        name: 'Universe ${nextIndex + 1}',
        universe: nextIndex,
      ),
    ];
  }

  void updateUniverse(String id, UniverseConfig Function(UniverseConfig current) updater) {
    state = [
      for (final universe in state)
        if (universe.id == id) updater(universe) else universe,
    ];
  }

  void removeUniverse(String id) {
    state = state.where((universe) => universe.id != id).toList();
  }

  void loadAll(List<UniverseConfig> universes) {
    state = universes;
  }

  void reset() {
    state = const [UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0)];
  }
}

class ConnectionStatus {
  final bool attempted;
  final bool success;
  final Duration? latency;
  final String? error;

  const ConnectionStatus({
    this.attempted = false,
    this.success = false,
    this.latency,
    this.error,
  });
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
      return ConnectionStatusNotifier(ref.watch(artNetServiceProvider));
    });

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  final ArtNetService _service;

  ConnectionStatusNotifier(this._service) : super(const ConnectionStatus());

  Future<void> testConnection(ArtNetSettings settings) async {
    if (!_service.isConnected) {
      await _service.connect(settings);
    } else {
      _service.updateSettings(settings);
    }
    final result = await _service.testConnection();
    state = ConnectionStatus(
      attempted: true,
      success: result.success,
      latency: result.latency,
      error: result.success ? null : 'No ArtPollReply received from ${settings.host}',
    );
  }
}

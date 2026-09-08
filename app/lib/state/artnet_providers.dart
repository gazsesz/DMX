import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      return ArtNetSettingsNotifier();
    });

class ArtNetSettingsNotifier extends StateNotifier<ArtNetSettings> {
  ArtNetSettingsNotifier() : super(const ArtNetSettings());

  void update(ArtNetSettings Function(ArtNetSettings current) updater) {
    state = updater(state);
  }
}

final universesProvider =
    StateNotifierProvider<UniversesNotifier, List<UniverseConfig>>((ref) {
      return UniversesNotifier();
    });

class UniversesNotifier extends StateNotifier<List<UniverseConfig>> {
  UniversesNotifier()
    : super(const [
        UniverseConfig(id: 'u1', name: 'Front Wash', universe: 0),
        UniverseConfig(id: 'u2', name: 'Moving Heads', universe: 1),
        UniverseConfig(id: 'u3', name: 'FX / Strobes', universe: 2),
      ]);

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
    state = const [
      UniverseConfig(id: 'u1', name: 'Front Wash', universe: 0),
      UniverseConfig(id: 'u2', name: 'Moving Heads', universe: 1),
      UniverseConfig(id: 'u3', name: 'FX / Strobes', universe: 2),
    ];
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

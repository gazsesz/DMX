import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/artnet/artnet_service.dart';
import '../core/playback/master_channels.dart';
import '../models/artnet_settings.dart';
import '../models/patched_fixture.dart';
import '../models/universe_config.dart';
import 'fixture_providers.dart';
import 'provider_reader.dart';

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
const _prefDemoMode = 'artnet.demoMode';
const prefOutputProtocol = 'artnet.protocol';
const prefSacnPriority = 'artnet.sacnPriority';

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
    await prefs.setBool(_prefDemoMode, settings.demoMode);
    await prefs.setString(prefOutputProtocol, settings.protocol.name);
    await prefs.setInt(prefSacnPriority, settings.sacnPriority);
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

/// The grand master, 0..1. Lives in a provider so the dock can drive it and
/// anything else can read the current level.
///
/// Like [lastPlayedProvider] it has to be *alive* to do its job — it keeps
/// the service's channel mask in step with the patch — so [watchGrandMaster]
/// brings it up at startup rather than waiting for the dock to be shown.
final grandMasterProvider = StateNotifierProvider<GrandMasterNotifier, double>((ref) {
  final notifier = GrandMasterNotifier(ref.watch(artNetServiceProvider));
  ref.listen<List<PatchedFixture>>(
    patchedFixturesProvider,
    (_, next) => notifier.refreshChannels(next, ref.read(universesProvider)),
    fireImmediately: true,
  );
  ref.listen<List<UniverseConfig>>(
    universesProvider,
    (_, next) => notifier.refreshChannels(ref.read(patchedFixturesProvider), next),
  );
  return notifier;
});

class GrandMasterNotifier extends StateNotifier<double> {
  final ArtNetService _service;

  GrandMasterNotifier(this._service) : super(_service.master);

  void set(double level) {
    final clamped = level.clamp(0.0, 1.0);
    _service.master = clamped;
    state = clamped;
  }

  void refreshChannels(List<PatchedFixture> fixtures, List<UniverseConfig> universes) {
    _service.setMasterChannels(masterChannelsFor(fixtures, universes));
  }
}

/// Brings [grandMasterProvider] into existence so it starts tracking the
/// patch. Called once at startup.
void watchGrandMaster(ReadProvider read) => read(grandMasterProvider);

class ConnectionStatus {
  final bool attempted;
  final bool success;
  final Duration? latency;
  final String? error;

  /// A poll is in flight. The status indicator shows this rather than
  /// flicking to red for the second it takes the node to answer.
  final bool checking;

  /// Demo mode is on, so there is nothing to reach and "offline" is the
  /// expected, correct state — never an error.
  final bool demo;

  /// Output is sACN only. There's no poll/reply handshake in E1.31 and the
  /// packets go to a multicast group rather than a node's address, so there
  /// is nothing to verify — "no answer" here means the protocol has no
  /// answer to give, not that anything is wrong.
  final bool unverified;

  const ConnectionStatus({
    this.attempted = false,
    this.success = false,
    this.latency,
    this.error,
    this.checking = false,
    this.demo = false,
    this.unverified = false,
  });

  ConnectionStatus copyWith({bool? checking}) => ConnectionStatus(
    attempted: attempted,
    success: success,
    latency: latency,
    error: error,
    checking: checking ?? this.checking,
    demo: demo,
    unverified: unverified,
  );
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
      return ConnectionStatusNotifier(
        ref.watch(artNetServiceProvider),
        () => ref.read(artNetSettingsProvider),
      );
    });

/// How often the node is re-polled once auto-connect is running. Short
/// enough that unplugging the node shows up while you're still looking at
/// the tablet, long enough not to be traffic worth thinking about.
const _watchdogInterval = Duration(seconds: 10);

class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  final ArtNetService _service;
  final ArtNetSettings Function() _currentSettings;

  Timer? _watchdog;
  bool _polling = false;

  ConnectionStatusNotifier(this._service, this._currentSettings) : super(const ConnectionStatus());

  /// Opens the socket and starts verifying the node in the background,
  /// repeatedly. Called once at startup so the status indicator is
  /// meaningful without anyone pressing Test, and again whenever the
  /// connection settings change.
  Future<void> startAutoConnect() async {
    _watchdog?.cancel();
    await _reconnect();
    unawaited(_poll());
    _watchdog = Timer.periodic(_watchdogInterval, (_) => unawaited(_poll()));
  }

  /// The Test button: same check, but awaited so the button can show a
  /// spinner and the caller knows when there's a result to read.
  Future<void> testConnection() async {
    await _reconnect();
    await _poll();
  }

  Future<void> _reconnect() async {
    final settings = _currentSettings();
    try {
      if (!_service.isConnected || _service.isDemoMode != settings.demoMode) {
        await _service.connect(settings);
      } else {
        _service.updateSettings(settings);
      }
    } catch (e) {
      state = ConnectionStatus(attempted: true, success: false, error: 'Could not open the socket: $e');
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    final settings = _currentSettings();
    if (settings.demoMode) {
      state = const ConnectionStatus(attempted: true, success: true, demo: true);
      return;
    }
    if (!settings.protocol.sendsArtNet) {
      // ArtPoll is an Art-Net thing. Sending it while the rig is on sACN
      // would mean a permanent red warning about a reply nothing was ever
      // going to send.
      state = ConnectionStatus(
        attempted: true,
        success: _service.isConnected,
        unverified: true,
        error: _service.isConnected ? null : 'Socket not open',
      );
      return;
    }
    _polling = true;
    if (mounted) state = state.copyWith(checking: true);
    try {
      // Re-open if the socket went away (Wi-Fi dropped, demo mode toggled
      // off) — otherwise the poll would fail for a reason the user can't
      // see and can only fix by restarting the app.
      if (!_service.isConnected) await _reconnect();
      final result = await _service.testConnection();
      if (!mounted) return;
      state = ConnectionStatus(
        attempted: true,
        success: result.success,
        latency: result.latency,
        error: result.success ? null : 'No ArtPollReply received from ${settings.host}',
      );
    } catch (e) {
      if (mounted) state = ConnectionStatus(attempted: true, success: false, error: e.toString());
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _watchdog = null;
    super.dispose();
  }
}

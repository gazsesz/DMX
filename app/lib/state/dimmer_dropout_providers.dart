import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/artnet/artnet_service.dart';
import '../core/playback/dimmer_dropout.dart';
import '../core/playback/master_channels.dart';
import '../models/patched_fixture.dart';
import '../models/universe_config.dart';
import 'artnet_providers.dart';
import 'fixture_providers.dart';

export '../core/playback/dimmer_dropout.dart' show DropoutSettings;

/// The dimmer dropout's settings, and the timer that runs it.
///
/// One controller app-wide, alive from the first time anything reads it: the
/// effect keeps running while the Layers screen is closed, and it follows the
/// patch so a fixture added mid-show is cut like the rest.
final dimmerDropoutProvider = StateNotifierProvider<DimmerDropoutController, DropoutSettings>((ref) {
  final controller = DimmerDropoutController(ref.watch(artNetServiceProvider));
  ref.listen<List<PatchedFixture>>(
    patchedFixturesProvider,
    (_, next) => controller.refreshScope(next, ref.read(universesProvider)),
    fireImmediately: true,
  );
  ref.listen<List<UniverseConfig>>(
    universesProvider,
    (_, next) => controller.refreshScope(ref.read(patchedFixturesProvider), next),
  );
  return controller;
});

class DimmerDropoutController extends StateNotifier<DropoutSettings> {
  final ArtNetService _service;
  final Random _random;

  /// Intensity channels the settings' fixtures can cut, per universe id —
  /// worked out when the settings or the patch change, not on every frame.
  Map<String, Set<int>> _scope = const {};
  List<PatchedFixture> _fixtures = const [];
  List<UniverseConfig> _universes = const [];

  /// True for the length of one dropout.
  bool _dark = false;
  Timer? _timer;

  DimmerDropoutController(this._service, {Random? random})
    : _random = random ?? Random(),
      super(const DropoutSettings());

  void update(DropoutSettings next) {
    final wasRunning = state.enabled;
    state = next;
    _rebuildScope();
    if (next.enabled && !wasRunning) {
      _start();
    } else if (!next.enabled && wasRunning) {
      stop();
    }
  }

  void refreshScope(List<PatchedFixture> fixtures, List<UniverseConfig> universes) {
    _fixtures = fixtures;
    _universes = universes;
    _rebuildScope();
  }

  void _rebuildScope() {
    final all = masterChannelsFor(_fixtures, _universes);
    final only = state.fixtureIds;
    _scope = only.isEmpty
        ? all
        : masterChannelsFor([for (final f in _fixtures) if (only.contains(f.id)) f], _universes);
  }

  Set<int> _darkIn(UniverseConfig universe) {
    if (!_dark) return const {};
    final scope = _scope[universe.id];
    if (scope == null || scope.isEmpty) return const {};
    final layers = state.targetLayerIds;
    return layers.isEmpty ? scope : _service.channelsOwnedBy(universe, layers, scope);
  }

  void _start() {
    _dark = false;
    _service.darkChannels = _darkIn;
    _service.fastRefresh = true;
    _scheduleDark();
  }

  void _scheduleDark() {
    _timer?.cancel();
    _timer = Timer(dropoutGap(state, _random), () {
      _dark = true;
      _service.refreshOutput();
      _timer = Timer(Duration(milliseconds: state.lengthMs), () {
        _dark = false;
        _service.refreshOutput();
        _scheduleDark();
      });
    });
  }

  /// Ends the effect and puts the light back at once.
  void stop() {
    _timer?.cancel();
    _timer = null;
    final wasDark = _dark;
    _dark = false;
    if (_service.darkChannels == _darkIn) {
      _service.darkChannels = null;
      _service.fastRefresh = false;
    }
    if (wasDark) _service.refreshOutput();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/artnet/artnet_service.dart';
import '../core/playback/dimmer_dropout.dart';
import '../core/playback/master_channels.dart';
import '../models/patched_fixture.dart';
import '../models/universe_config.dart';
import 'artnet_providers.dart';
import 'audio_providers.dart';
import 'fixture_providers.dart';

export '../core/playback/dimmer_dropout.dart' show DropoutSettings;

/// The dimmer dropout: what is running, and the timers that run it.
///
/// One controller app-wide, alive from the first time anything reads it: the
/// effect keeps running while the Layers screen is closed, and it follows the
/// patch so a fixture added mid-show is cut like the rest.
///
/// The state is what the user set by hand on the Layers screen. Two other
/// things can run a dropout beside it, and none of them changes the state:
/// - a running Smart Program's zone ([DimmerDropoutController.setProgramOverride]),
///   which replaces the hand-set one while it runs, and
/// - a chase playing on a layer ([DimmerDropoutController.setChaseDropout]),
///   which adds its own to that layer.
final dimmerDropoutProvider = StateNotifierProvider<DimmerDropoutController, DropoutSettings>((ref) {
  final controller = DimmerDropoutController(
    ref.watch(artNetServiceProvider),
    // Read lazily, per dropout: the beat source may not be listening yet when
    // the controller is built.
    beatEvents: () => ref.read(beatPredictorProvider).events,
    beatsListening: () => ref.read(activeBeatSourceProvider).isListening,
  );
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

/// One running dropout: its own settings, timer and dark phase, so a chase's
/// slow blips and the hand-set beat-locked ones don't share a clock.
class _Lane {
  DropoutSettings settings;

  /// Intensity channels this lane's fixtures can cut, per universe id.
  Map<String, Set<int>> scope = const {};

  /// True for the length of one dropout.
  bool dark = false;
  Timer? timer;
  StreamSubscription<DateTime>? beatSub;
  int beats = 0;

  _Lane(this.settings);

  void cancel() {
    timer?.cancel();
    timer = null;
    beatSub?.cancel();
    beatSub = null;
    dark = false;
  }
}

class DimmerDropoutController extends StateNotifier<DropoutSettings> {
  final ArtNetService _service;
  final Random _random;
  final Stream<DateTime> Function()? _beatEvents;
  final bool Function()? _beatsListening;

  List<PatchedFixture> _fixtures = const [];
  List<UniverseConfig> _universes = const [];

  /// What a running Smart Program wants, or null for the hand-set [state].
  DropoutSettings? _override;

  /// What the chase playing on each layer asks for, by layer id.
  final Map<String, DropoutSettings> _chases = {};

  final Map<String, _Lane> _lanes = {};

  DimmerDropoutController(
    this._service, {
    Random? random,
    Stream<DateTime> Function()? beatEvents,
    bool Function()? beatsListening,
  }) : _random = random ?? Random(),
       _beatEvents = beatEvents,
       _beatsListening = beatsListening,
       super(const DropoutSettings());

  void update(DropoutSettings next) {
    state = next;
    _sync();
  }

  /// A Smart Program's zone settings, or null once it lets go. Disabled
  /// settings mean "no hand-set dropout while this is on", which is not the
  /// same as null: the hand-set one is held back, not merely absent.
  void setProgramOverride(DropoutSettings? settings) {
    if (settings == _override) return;
    _override = settings;
    _sync();
  }

  /// The dropout of the chase playing on [layerId], or null when it stops. Only
  /// that layer is cut, whatever the settings' own layer list says.
  void setChaseDropout(String layerId, DropoutSettings? settings) {
    final wanted = settings != null && settings.enabled ? settings.copyWith(targetLayerIds: {layerId}) : null;
    if (wanted == _chases[layerId]) return;
    if (wanted == null) {
      _chases.remove(layerId);
    } else {
      _chases[layerId] = wanted;
    }
    _sync();
  }

  void refreshScope(List<PatchedFixture> fixtures, List<UniverseConfig> universes) {
    _fixtures = fixtures;
    _universes = universes;
    for (final lane in _lanes.values) {
      lane.scope = _scopeFor(lane.settings);
    }
  }

  Map<String, Set<int>> _scopeFor(DropoutSettings settings) {
    final only = settings.fixtureIds;
    return masterChannelsFor(
      only.isEmpty ? _fixtures : [for (final f in _fixtures) if (only.contains(f.id)) f],
      _universes,
    );
  }

  /// Brings the running lanes in line with what is wanted: started, retuned
  /// or stopped. A lane whose settings did not change keeps its phase.
  void _sync() {
    final wanted = <String, DropoutSettings>{};
    final program = _override;
    if (program != null) {
      if (program.enabled) wanted['program'] = program;
    } else if (state.enabled) {
      wanted['manual'] = state;
    }
    for (final entry in _chases.entries) {
      wanted['chase:${entry.key}'] = entry.value;
    }

    var changed = false;
    for (final key in _lanes.keys.toList()) {
      if (wanted.containsKey(key)) continue;
      final gone = _lanes.remove(key)!;
      changed = gone.dark || changed;
      gone.cancel();
    }
    for (final entry in wanted.entries) {
      final lane = _lanes[entry.key];
      if (lane == null) {
        _startLane(entry.key, entry.value);
      } else if (lane.settings != entry.value) {
        lane.cancel();
        lane.settings = entry.value;
        lane.scope = _scopeFor(entry.value);
        _scheduleLane(lane);
        changed = true;
      }
    }

    if (_lanes.isEmpty) {
      if (_service.darkChannels == _darkIn) {
        _service.darkChannels = null;
        _service.fastRefresh = false;
      }
    } else {
      _service.darkChannels = _darkIn;
      _service.fastRefresh = true;
    }
    if (changed) _service.refreshOutput();
  }

  Set<int> _darkIn(UniverseConfig universe) {
    Set<int>? out;
    for (final lane in _lanes.values) {
      if (!lane.dark) continue;
      final scope = lane.scope[universe.id];
      if (scope == null || scope.isEmpty) continue;
      final layers = lane.settings.targetLayerIds;
      final cut = layers.isEmpty ? scope : _service.channelsOwnedBy(universe, layers, scope);
      if (cut.isEmpty) continue;
      (out ??= <int>{}).addAll(cut);
    }
    return out ?? const {};
  }

  void _startLane(String key, DropoutSettings settings) {
    final lane = _Lane(settings)..scope = _scopeFor(settings);
    _lanes[key] = lane;
    _scheduleLane(lane);
  }

  bool get _beatsAvailable => (_beatsListening?.call() ?? false) && _beatEvents != null;

  /// Starts a lane's clock: the beat when it is locked to one and a source is
  /// listening, the timer otherwise.
  void _scheduleLane(_Lane lane) {
    lane.cancel();
    if (lane.settings.onBeat && _beatsAvailable) {
      lane.beats = 0;
      lane.beatSub = _beatEvents!().listen((_) {
        if (++lane.beats % lane.settings.beatEvery != 0) return;
        _goDark(lane, then: () {});
      });
      return;
    }
    lane.timer = Timer(dropoutGap(lane.settings, _random), () {
      // A beat source that came up since this lane started takes it over.
      if (lane.settings.onBeat && _beatsAvailable) {
        _scheduleLane(lane);
        return;
      }
      _goDark(lane, then: () => _scheduleLane(lane));
    });
  }

  void _goDark(_Lane lane, {required void Function() then}) {
    if (!_lanes.containsValue(lane)) return;
    lane.dark = true;
    _service.refreshOutput();
    lane.timer?.cancel();
    lane.timer = Timer(Duration(milliseconds: lane.settings.lengthMs), () {
      lane.dark = false;
      _service.refreshOutput();
      then();
    });
  }

  /// Ends every dropout and puts the light back at once.
  void stop() {
    final wasDark = _lanes.values.any((l) => l.dark);
    for (final lane in _lanes.values) {
      lane.cancel();
    }
    _lanes.clear();
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

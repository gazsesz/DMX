import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/artnet/artnet_service.dart';
import '../core/live/live_engine.dart';
import '../models/live_grid.dart';
import '../models/universe_config.dart';
import 'artnet_providers.dart';
import 'audio_providers.dart';
import 'fixture_group_providers.dart';
import 'fixture_providers.dart';
import 'movement_live_providers.dart';
import 'stage_providers.dart';
import 'tempo_providers.dart';

const prefLivePadMode = 'live.padMode';
const prefLiveQuantize = 'live.quantize';

/// The project's Live Grid. Starts as [LiveGrid.starter] so the screen has
/// something to play the first time it opens.
final liveGridProvider = StateNotifierProvider<LiveGridNotifier, LiveGrid>((ref) => LiveGridNotifier());

class LiveGridNotifier extends StateNotifier<LiveGrid> {
  LiveGridNotifier() : super(LiveGrid.starter());

  /// From a project file; null or empty (older files) → the starter grid.
  void load(LiveGrid? grid) => state = (grid == null || grid.isEmpty) ? LiveGrid.starter() : grid;

  void setClip(String laneId, int row, LiveClip? clip) => state = state.withClip(laneId, row, clip);

  void updateLane(LiveLane lane) => state = state.withLane(lane);

  void renameRow(int row, String name) {
    if (row < 0 || row >= state.rows.length) return;
    state = state.copyWith(rows: [for (var i = 0; i < state.rows.length; i++) i == row ? name : state.rows[i]]);
  }

  void addRow(String name) => state = state.copyWith(rows: [...state.rows, name]);
}

/// Device-level Live settings: what a pad tap does and when a launch lands.
class LivePrefs {
  final LivePadMode padMode;
  final LiveQuantize quantize;

  const LivePrefs({this.padMode = LivePadMode.selectThenGo, this.quantize = LiveQuantize.bar});

  LivePrefs copyWith({LivePadMode? padMode, LiveQuantize? quantize}) =>
      LivePrefs(padMode: padMode ?? this.padMode, quantize: quantize ?? this.quantize);
}

final livePrefsProvider = StateNotifierProvider<LivePrefsNotifier, LivePrefs>((ref) => LivePrefsNotifier());

class LivePrefsNotifier extends StateNotifier<LivePrefs> {
  LivePrefsNotifier() : super(const LivePrefs()) {
    _load();
  }

  bool _touched = false;

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (_touched || !mounted) return;
      state = LivePrefs(
        padMode: LivePadMode.parse(sp.getString(prefLivePadMode)),
        quantize: LiveQuantize.parse(sp.getString(prefLiveQuantize)),
      );
    } catch (_) {
      // No prefs (tests, first run): keep the defaults.
    }
  }

  void setPadMode(LivePadMode mode) => _set(state.copyWith(padMode: mode));

  void setQuantize(LiveQuantize quantize) => _set(state.copyWith(quantize: quantize));

  void _set(LivePrefs next) {
    _touched = true;
    state = next;
    unawaited(() async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(prefLivePadMode, next.padMode.name);
        await sp.setString(prefLiveQuantize, next.quantize.name);
      } catch (_) {}
    }());
  }
}

class _ArtNetLiveOutput implements LiveOutput {
  final ArtNetService service;
  _ArtNetLiveOutput(this.service);

  @override
  void claimLayer(String layer) => service.claimLayer(layer);

  @override
  void setLayerChannel(UniverseConfig universe, int channel, int value, String layer) =>
      service.setLayerChannel(universe, channel, value, layer);

  @override
  void releaseLayer(String layer) => service.releaseLayer(layer);

  @override
  void flush(UniverseConfig universe) => service.flush(universe);

  @override
  int getChannelValue(UniverseConfig universe, int channel) => service.getChannelValue(universe, channel);
}

/// The engine behind the Live screen. Ticks at 40 fps while anything runs
/// or waits for its launch; idle otherwise.
final liveEngineProvider = Provider<LiveEngine>((ref) {
  final engine = LiveEngine(
    output: _ArtNetLiveOutput(ref.watch(artNetServiceProvider)),
    grid: () => ref.read(liveGridProvider),
    rig: () => LiveRig(
      fixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      groups: ref.read(fixtureGroupsProvider),
      stage: ref.read(stagePlanProvider),
    ),
    fallbackBpm: () => ref.read(tempoProvider).bpm,
    movementLive: () => ref.read(movementLiveProvider),
  );
  final clock = Stopwatch()..start();
  double seconds() => clock.elapsedMicroseconds / 1e6;

  final notifier = ref.read(liveStatusProvider.notifier);
  Timer? ticker;
  var ticks = 0;
  void ensureTicking() {
    if (engine.isActive) {
      ticker ??= Timer.periodic(const Duration(milliseconds: 25), (_) {
        engine.tick(seconds());
        // The beat readout on screen moves even when nothing new is selected.
        if (++ticks % 5 == 0) notifier.state = engine.status;
        if (!engine.isActive) {
          ticker?.cancel();
          ticker = null;
          notifier.state = engine.status;
        }
      });
    }
  }

  engine.onChange = () {
    ensureTicking();
    notifier.state = engine.status;
  };

  final beats = ref.watch(beatPredictorProvider).events.listen((_) => engine.onBeat(seconds()));

  ref.onDispose(() {
    ticker?.cancel();
    beats.cancel();
    engine.stopAll();
  });
  return engine;
});

final liveStatusProvider = StateProvider<LiveStatus>((ref) => const LiveStatus());

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_group.dart';
import '../../models/live_grid.dart';
import '../../models/movement_fx.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../models/stage_plan.dart';
import '../../models/universe_config.dart';
import '../movement/movement_engine.dart';
import '../playback/color_override.dart';
import '../positions/group_positions.dart';

/// Where the Live engine sends its channel values. [ArtNetService] does
/// this; tests use a map.
abstract class LiveOutput {
  void claimLayer(String layer);
  void setLayerChannel(UniverseConfig universe, int channel, int value, String layer);
  void releaseLayer(String layer);
  void flush(UniverseConfig universe);
  int getChannelValue(UniverseConfig universe, int channel);
}

/// The rig the grid plays on, read fresh every tick so a patch edit shows
/// up without restarting anything.
class LiveRig {
  final List<PatchedFixture> fixtures;
  final List<UniverseConfig> universes;
  final List<FixtureGroup> groups;
  final StagePlan stage;

  const LiveRig({
    this.fixtures = const [],
    this.universes = const [],
    this.groups = const [],
    this.stage = const StagePlan(),
  });
}

/// What the screen draws: which row runs on each lane, which is NEXT, and
/// the clock.
class LiveStatus {
  /// lane id → running row.
  final Map<String, int> running;

  /// lane id → selected (NEXT) row.
  final Map<String, int> queued;

  /// lane id → the beat the queued clip starts on, once GO (or a direct
  /// launch) has armed it.
  final Map<String, double> armedAt;

  final double beat;
  final double bpm;
  final bool frozen;

  const LiveStatus({
    this.running = const {},
    this.queued = const {},
    this.armedAt = const {},
    this.beat = 0,
    this.bpm = 120,
    this.frozen = false,
  });

  /// 1..4 within the bar.
  int get beatInBar => ((beat + 0.01).floor() % 4) + 1;

  bool get anyRunning => running.isNotEmpty;
}

/// Starts and stops a Show lane's Banks / Chases / Scenes on the app's
/// regular players. The engine only decides *when*.
abstract class LiveShowHost {
  /// Completes once the player has taken its layers (a Chase may first
  /// wait for the beat source).
  Future<void> start(LiveLane lane, LiveShowRef show);
  void stop(LiveLane lane);

  /// Whether what [lane] started is still playing (it may have been
  /// stopped from the Dashboard or another screen).
  bool isPlaying(LiveLane lane);
}

/// The layer id a lane's clips write on (see `ArtNetService.claimLayer`).
String liveLayerId(String laneId) => 'live:$laneId';

/// Holds heads' shutters open while the grid runs, under every lane: a
/// Beam lane started later wins the strobe channel.
const liveShutterLayer = 'live:shutter';

/// Plays a [LiveGrid]: one effect per lane, each lane on its own output
/// layer so it only ever writes its own attribute group.
///
/// Time is counted in beats. With a beat source the count locks onto the
/// incoming beats; without one it runs at [fallbackBpm]. A bar is four
/// beats from the downbeat ([markDownbeat] moves it).
class LiveEngine {
  final LiveOutput output;
  final LiveGrid Function() grid;
  final LiveRig Function() rig;
  final double Function() fallbackBpm;
  final MovementLive Function() movementLive;
  final LiveShowHost? shows;

  LiveEngine({
    required this.output,
    required this.grid,
    required this.rig,
    double Function()? fallbackBpm,
    MovementLive Function()? movementLive,
    this.shows,
  }) : fallbackBpm = fallbackBpm ?? (() => 120),
       movementLive = movementLive ?? (() => MovementLive.neutral);

  void Function()? onChange;

  final Map<String, int> _running = {};
  final Map<String, int> _queued = {};
  final Map<String, double> _armed = {};
  final Map<String, double> _startBeat = {};
  final Map<String, double> _freePhase = {};
  final Map<String, Map<String, PanTilt>> _glideFrom = {};
  final Map<String, Map<String, PanTilt>> _previous = {};
  final Map<String, double> _glideStart = {};

  /// Lanes whose running clip is a Bank / Chase / Scene on the regular
  /// players rather than an effect this engine writes.
  final Set<String> _showLanes = {};

  double _beat = 0;
  double _bpm = 120;
  double? _seconds;
  double? _lastBeatSeconds;
  bool _frozen = false;
  bool _shutterClaimed = false;

  /// Seconds since the engine was made, advanced by [tick].
  double get _now => _seconds ?? 0;

  LiveStatus get status => LiveStatus(
    running: Map.unmodifiable(_running),
    queued: Map.unmodifiable(_queued),
    armedAt: Map.unmodifiable(_armed),
    beat: _beat,
    bpm: _bpm,
    frozen: _frozen,
  );

  bool get isActive => _running.isNotEmpty || _armed.isNotEmpty;

  // --- Selection --------------------------------------------------------

  /// A tap on a clip. Select + GO: marks it NEXT (a second tap clears it).
  /// Launch directly: arms it for the next [quantize] boundary.
  void select(String laneId, int row, {required LivePadMode mode, required LiveQuantize quantize}) {
    if (grid().clipAt(laneId, row) == null) return;
    if (_queued[laneId] == row && mode == LivePadMode.selectThenGo) {
      _queued.remove(laneId);
      _armed.remove(laneId);
    } else {
      _queued[laneId] = row;
      _armed.remove(laneId);
      if (mode == LivePadMode.launchDirectly) _arm(laneId, quantize);
    }
    _changed();
  }

  /// A tap on a row's scene button: selects that row on every lane that has
  /// a clip there. Lanes without one keep what they run.
  void selectRow(int row, {required LivePadMode mode, required LiveQuantize quantize}) {
    final g = grid();
    for (final lane in g.lanes) {
      if (g.clipAt(lane.id, row) == null) continue;
      _queued[lane.id] = row;
      _armed.remove(lane.id);
      if (mode == LivePadMode.launchDirectly) _arm(lane.id, quantize);
    }
    _changed();
  }

  /// Arms every NEXT clip for the next [quantize] boundary.
  void go({required LiveQuantize quantize}) {
    for (final laneId in _queued.keys) {
      _arm(laneId, quantize);
    }
    if (quantize == LiveQuantize.now) _commitDue();
    _changed();
  }

  /// Clears every NEXT selection that GO has not armed yet.
  void clearSelection() {
    _queued.removeWhere((lane, _) => !_armed.containsKey(lane));
    _changed();
  }

  void stopLane(String laneId) {
    _stopShow(laneId);
    _running.remove(laneId);
    _queued.remove(laneId);
    _armed.remove(laneId);
    _forgetLane(laneId);
    output.releaseLayer(liveLayerId(laneId));
    if (_running.isEmpty) _releaseShutter();
    _changed();
  }

  void stopAll() {
    for (final laneId in _showLanes.toList()) {
      _stopShow(laneId);
    }
    for (final laneId in {..._running.keys, ..._queued.keys}) {
      output.releaseLayer(liveLayerId(laneId));
      _forgetLane(laneId);
    }
    _running.clear();
    _queued.clear();
    _armed.clear();
    _releaseShutter();
    _changed();
  }

  void setFrozen(bool value) {
    if (_frozen == value) return;
    _frozen = value;
    _changed();
  }

  /// Makes the beat that just passed (or is about to land) the first of
  /// the bar.
  void markDownbeat() {
    final whole = _beat.round();
    _beat -= (whole % 4).toDouble();
    if (_beat < 0) _beat += 4;
    _changed();
  }

  // --- Clock ------------------------------------------------------------

  /// A beat from the active source, at [seconds] on the same clock [tick]
  /// uses.
  void onBeat(double seconds) {
    final last = _lastBeatSeconds;
    _lastBeatSeconds = seconds;
    if (last != null) {
      final gap = seconds - last;
      if (gap >= 0.2 && gap <= 2) _bpm = 60 / gap;
    }
    if (_frozen) return;
    // Pull the count onto the beat: half the error now, the rest over the
    // next beats, so a late beat never makes anything jump.
    final target = _beat.roundToDouble();
    _beat += (target - _beat) * 0.5;
    _commitDue();
  }

  /// Advances to [seconds] and writes one frame.
  void tick(double seconds) {
    final previous = _seconds ?? seconds;
    _seconds = seconds;
    final dt = (seconds - previous).clamp(0.0, 0.5);
    // No beats for two seconds: the source is quiet or off — run on the
    // set tempo instead of the last heard one.
    final heard = _lastBeatSeconds;
    if (heard == null || seconds - heard > 2) _bpm = fallbackBpm().clamp(20.0, 300.0);
    if (!_frozen) {
      _beat += dt * _bpm / 60;
      for (final lane in _running.keys) {
        _freePhase[lane] = (_freePhase[lane] ?? 0) + dt;
      }
    }
    final committed = _commitDue();
    final dropped = _dropFinishedShows();
    if (!_frozen) _render();
    if (committed || dropped) _changed();
  }

  /// A lane whose Bank / Chase / Scene clip was stopped somewhere else stops
  /// counting as running. Checked a second after start, so a chase still
  /// opening its beat source isn't taken for stopped.
  bool _dropFinishedShows() {
    final host = shows;
    if (host == null) return false;
    final g = grid();
    var any = false;
    for (final laneId in _showLanes.toList()) {
      final lane = g.lane(laneId);
      if (lane != null && _now - (_glideStart[laneId] ?? _now) < 1) continue;
      if (lane != null && host.isPlaying(lane)) continue;
      _showLanes.remove(laneId);
      _running.remove(laneId);
      _forgetLane(laneId);
      any = true;
    }
    if (any && _running.isEmpty) _releaseShutter();
    return any;
  }

  /// Re-claims every running effect lane's layer, oldest first, so they
  /// win their channels over a Bank / Chase / Scene started after them.
  void _keepEffectsOnTop() {
    final effects = [
      for (final laneId in _running.keys)
        if (!_showLanes.contains(laneId)) laneId,
    ]..sort((a, b) => (_startBeat[a] ?? 0).compareTo(_startBeat[b] ?? 0));
    for (final laneId in effects) {
      output.claimLayer(liveLayerId(laneId));
    }
  }

  void _stopShow(String laneId) {
    if (!_showLanes.remove(laneId)) return;
    final lane = grid().lane(laneId);
    if (lane != null) shows?.stop(lane);
  }

  void _arm(String laneId, LiveQuantize quantize) {
    _armed[laneId] = switch (quantize) {
      LiveQuantize.now => _beat,
      LiveQuantize.beat => (_beat - 0.02).floorToDouble() + 1,
      LiveQuantize.bar => ((_beat - 0.02) / 4).floorToDouble() * 4 + 4,
    };
  }

  bool _commitDue() {
    var any = false;
    for (final entry in _armed.entries.toList()) {
      if (entry.value > _beat + 1e-6) continue;
      final laneId = entry.key;
      final row = _queued.remove(laneId);
      _armed.remove(laneId);
      if (row == null) continue;
      _start(laneId, row, entry.value);
      any = true;
    }
    return any;
  }

  void _start(String laneId, int row, double atBeat) {
    final g = grid();
    final lane = g.lane(laneId);
    final show = g.clipAt(laneId, row)?.show;
    // Whatever Bank / Chase / Scene this lane had going makes way first.
    _stopShow(laneId);
    if (lane != null && (show != null || lane.kind == LiveLaneKind.show)) {
      // Any lane's clip can start one of the project's own Banks, Chases or
      // Scenes instead of an effect.
      output.releaseLayer(liveLayerId(laneId));
      _forgetLane(laneId);
      if (show == null) {
        _running.remove(laneId);
        return;
      }
      _running[laneId] = row;
      _startBeat[laneId] = atBeat;
      _glideStart[laneId] = _now;
      _showLanes.add(laneId);
      final started = shows?.start(lane, show);
      // Effect lanes stay on top of what the Grid starts: the Bank / Chase
      // / Scene is the base look, the lanes override only their own part.
      _keepEffectsOnTop();
      started?.then((_) => _keepEffectsOnTop());
      return;
    }
    if (!_shutterClaimed) {
      output.claimLayer(liveShutterLayer);
      _shutterClaimed = true;
    }
    _running[laneId] = row;
    _startBeat[laneId] = atBeat;
    _freePhase[laneId] = 0;
    _glideStart[laneId] = _now;
    _glideFrom.remove(laneId);
    output.claimLayer(liveLayerId(laneId));
  }

  void _forgetLane(String laneId) {
    _startBeat.remove(laneId);
    _freePhase.remove(laneId);
    _glideFrom.remove(laneId);
    _glideStart.remove(laneId);
    _previous.remove(laneId);
  }

  void _releaseShutter() {
    if (!_shutterClaimed) return;
    output.releaseLayer(liveShutterLayer);
    _shutterClaimed = false;
  }

  void _changed() => onChange?.call();

  // --- Output -----------------------------------------------------------

  void _render() {
    if (_running.isEmpty) return;
    final g = grid();
    final r = rig();
    final universes = {for (final u in r.universes) u.id: u};
    final touched = <UniverseConfig>{};

    // Level first: pars without a dimmer take it on their colour.
    final levels = <String, double>{};
    final beamLanes = <String>{};
    for (final entry in _running.entries) {
      final lane = g.lane(entry.key);
      final clip = g.clipAt(entry.key, entry.value);
      if (lane == null || clip == null || _showLanes.contains(lane.id)) continue;
      if (lane.kind == LiveLaneKind.beam) {
        for (final f in targetsOf(lane, r)) {
          beamLanes.add(f.id);
        }
      }
      if (lane.kind != LiveLaneKind.level || clip.level == null) continue;
      final fixtures = targetsOf(lane, r);
      for (var i = 0; i < fixtures.length; i++) {
        levels[fixtures[i].id] = levelValue(clip.level!, _localBeat(lane), i, fixtures.length) * lane.amount;
      }
    }

    for (final entry in _running.entries) {
      final lane = g.lane(entry.key);
      final clip = g.clipAt(entry.key, entry.value);
      if (lane == null || clip == null || _showLanes.contains(lane.id)) continue;
      final layer = liveLayerId(lane.id);
      final fixtures = targetsOf(lane, r);
      void write(PatchedFixture f, int offset, int value) {
        final universe = universes[f.universeId];
        if (universe == null) return;
        final channel = f.startChannel + offset;
        if (channel < 0 || channel > 511) return;
        output.setLayerChannel(universe, channel, value, layer);
        touched.add(universe);
      }

      switch (lane.kind) {
        case LiveLaneKind.moves:
          if (clip.moves != null) _renderMoves(lane, clip.moves!, fixtures, r, universes, touched);
        case LiveLaneKind.colors:
          if (clip.colors == null) break;
          for (var i = 0; i < fixtures.length; i++) {
            final f = fixtures[i];
            final rgb = colorValue(clip.colors!, _localBeat(lane), i, fixtures.length);
            final hasDimmer = f.profile.channels.any((c) => c.function.isDimmer);
            final scale = (hasDimmer ? 1.0 : (levels[f.id] ?? 1.0)) * lane.amount;
            _writeColor(f, rgb, scale, write);
          }
        case LiveLaneKind.level:
          for (final f in fixtures) {
            final level = levels[f.id] ?? 0;
            for (final c in f.profile.channels) {
              if (c.function.isDimmer) write(f, c.offset, (level * 255).round());
            }
          }
        case LiveLaneKind.beam:
          if (clip.beam == null) break;
          for (final f in fixtures) {
            _writeBeam(f, clip.beam!, write);
          }
        case LiveLaneKind.show:
          // Played by the regular players; nothing to write here.
          break;
      }
    }

    // Open shutters on lit heads no Beam lane owns, so a Level lane alone
    // makes light.
    for (final f in r.fixtures) {
      if (beamLanes.contains(f.id) || !levels.containsKey(f.id)) continue;
      final universe = universes[f.universeId];
      if (universe == null) continue;
      for (final c in f.profile.channels) {
        if (c.function != ChannelFunction.strobe) continue;
        final open = shutterOpenValue(c.capabilities);
        if (open == null) continue;
        output.setLayerChannel(universe, f.startChannel + c.offset, open, liveShutterLayer);
        touched.add(universe);
      }
    }

    for (final universe in touched) {
      output.flush(universe);
    }
  }

  double _localBeat(LiveLane lane) => (_beat - (_startBeat[lane.id] ?? _beat)) * lane.speed;

  void _renderMoves(
    LiveLane lane,
    MovementFx clipFx,
    List<PatchedFixture> fixtures,
    LiveRig r,
    Map<String, UniverseConfig> universes,
    Set<UniverseConfig> touched,
  ) {
    final live = movementLive();
    final fx = live.applyTo(
      lane.amount >= 1
          ? clipFx
          : clipFx.copyWith(sizePanDeg: clipFx.sizePanDeg * lane.amount, sizeTiltDeg: clipFx.sizeTiltDeg * lane.amount),
    );
    final heads = movementHeads(fx, fixtures, r.groups);
    if (heads.isEmpty) return;
    final double phase;
    if (fx.beatLocked && fx.beats > 0) {
      phase = (_localBeat(lane) * live.speed / fx.beats) % 1.0;
    } else {
      final period = fx.periodSec <= 0 ? 4.0 : fx.periodSec;
      phase = ((_freePhase[lane.id] ?? 0) * lane.speed * live.speed / period) % 1.0;
    }
    final frame = movementFrame(fx, heads, phase, r.stage, previous: _previous[lane.id] ?? const {});
    _previous[lane.id] = frame;

    // Glide from wherever the heads were for the first half second, so a
    // new clip never snaps them across the stage.
    final since = _now - (_glideStart[lane.id] ?? -10);
    final t = (since / 0.5).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    final from = _glideFrom.putIfAbsent(lane.id, () {
      final start = <String, PanTilt>{};
      for (final head in heads) {
        final universe = universes[head.fixture.universeId];
        if (universe == null) continue;
        final base = head.fixture.startChannel;
        int read(int? offset) => offset == null ? 0 : output.getChannelValue(universe, base + offset);
        start[head.fixture.id] = PanTilt(
          (read(head.panOffset) << 8) | read(head.panFineOffset),
          (read(head.tiltOffset) << 8) | read(head.tiltFineOffset),
        );
      }
      return start;
    });

    final layer = liveLayerId(lane.id);
    for (final head in heads) {
      final universe = universes[head.fixture.universeId];
      final target = frame[head.fixture.id];
      if (universe == null || target == null) continue;
      final start = from[head.fixture.id] ?? target;
      final p = lerpPanTilt(start, target, eased);
      final base = head.fixture.startChannel;
      void w(int? offset, int value) {
        if (offset == null) return;
        final ch = base + offset;
        if (ch < 0 || ch > 511) return;
        output.setLayerChannel(universe, ch, value, layer);
      }

      w(head.panOffset, p.panCoarse);
      w(head.panFineOffset, p.panFine);
      w(head.tiltOffset, p.tiltCoarse);
      w(head.tiltFineOffset, p.tiltFine);
      touched.add(universe);
    }
  }

  final Map<String, int?> _wheelCache = {};

  void _writeColor(PatchedFixture f, int rgb, double scale, void Function(PatchedFixture, int, int) write) {
    final r = (rgb >> 16) & 255;
    final g = (rgb >> 8) & 255;
    final b = rgb & 255;
    final white = r == g && g == b ? r : 0;
    int s(int v) => (v * scale).round().clamp(0, 255);
    for (final c in f.profile.channels) {
      switch (c.function) {
        case ChannelFunction.red:
          write(f, c.offset, s(white > 0 ? 0 : r));
        case ChannelFunction.green:
          write(f, c.offset, s(white > 0 ? 0 : g));
        case ChannelFunction.blue:
          write(f, c.offset, s(white > 0 ? 0 : b));
        case ChannelFunction.white:
          write(f, c.offset, s(white));
        case ChannelFunction.amber:
        case ChannelFunction.uv:
          write(f, c.offset, 0);
        case ChannelFunction.colorWheel:
          if (c.capabilities.isEmpty) break;
          final key = '${f.profile.hashCode}:${c.offset}:$rgb';
          final value = _wheelCache.putIfAbsent(
            key,
            () => nearestWheelValue(c.capabilities, LiveColor('', '', r, g, b)),
          );
          if (value != null) write(f, c.offset, value);
        default:
          break;
      }
    }
    // RGB fixtures without a white emitter still need white as R=G=B.
    if (white > 0 && !f.profile.channels.any((c) => c.function == ChannelFunction.white)) {
      for (final c in f.profile.channels) {
        if (c.function == ChannelFunction.red ||
            c.function == ChannelFunction.green ||
            c.function == ChannelFunction.blue) {
          write(f, c.offset, s(white));
        }
      }
    }
  }

  void _writeBeam(PatchedFixture f, LiveBeamFx beam, void Function(PatchedFixture, int, int) write) {
    for (final c in f.profile.channels) {
      switch (c.function) {
        case ChannelFunction.gobo:
          if (beam.gobo != null) write(f, c.offset, beam.gobo!.clamp(0, 255));
        case ChannelFunction.strobe:
          final s = beam.strobe;
          if (s == null) break;
          final value = s <= 0 ? shutterOpenValue(c.capabilities) ?? 0 : strobeValue(c.capabilities, s);
          write(f, c.offset, value);
        case ChannelFunction.zoom:
          if (beam.zoom != null) write(f, c.offset, (beam.zoom! * 255).round().clamp(0, 255));
        case ChannelFunction.goboRotation:
          if (beam.goboRotation != null) write(f, c.offset, (beam.goboRotation! * 255).round().clamp(0, 255));
        case ChannelFunction.prism:
          if (beam.prism != null) write(f, c.offset, beam.prism!.clamp(0, 255));
        case ChannelFunction.prismRotation:
          if (beam.prismRotation != null) write(f, c.offset, (beam.prismRotation! * 255).round().clamp(0, 255));
        default:
          break;
      }
    }
  }

  /// Snapshot of what one universe holds now — for tests and the preview.
  Uint8List frameOf(UniverseConfig universe) =>
      Uint8List.fromList([for (var i = 0; i < 512; i++) output.getChannelValue(universe, i)]);
}

// --- Pure helpers (tested directly) ---------------------------------------

bool _hasPanTilt(PatchedFixture f) =>
    f.profile.channels.any((c) => c.function == ChannelFunction.pan) &&
    f.profile.channels.any((c) => c.function == ChannelFunction.tilt);

bool _drives(LiveLaneKind kind, PatchedFixture f) {
  final fns = f.profile.channels.map((c) => c.function);
  return switch (kind) {
    LiveLaneKind.moves => _hasPanTilt(f),
    LiveLaneKind.colors => fns.any((fn) => fn.isColorMix || fn == ChannelFunction.colorWheel),
    LiveLaneKind.level => fns.any((fn) => fn.isDimmer || fn.isColorMix),
    LiveLaneKind.beam => fns.any(
      (fn) =>
          fn == ChannelFunction.gobo ||
          fn == ChannelFunction.strobe ||
          fn == ChannelFunction.zoom ||
          fn == ChannelFunction.goboRotation ||
          fn.isPrism,
    ),
    LiveLaneKind.show => false,
  };
}

/// The fixtures [lane] drives on [rig], left to right on the stage.
List<PatchedFixture> targetsOf(LiveLane lane, LiveRig rig) {
  final inGroups = <String>{
    for (final g in rig.groups)
      if (lane.groupIds.contains(g.id)) ...g.fixtureIds,
  };
  final picked = rig.fixtures.where((f) {
    if (!_drives(lane.kind, f)) return false;
    return switch (lane.target) {
      LiveTargetKind.all => true,
      LiveTargetKind.heads => _hasPanTilt(f),
      LiveTargetKind.pars => !_hasPanTilt(f),
      LiveTargetKind.groups => inGroups.contains(f.id),
    };
  });
  return spreadOrder(picked);
}

double _frac(double x) => x - x.floorToDouble();

/// Fixture [index] of [count]'s level (0..1) at [beat] beats into the clip.
double levelValue(LiveLevelFx fx, double beat, int index, int count) {
  final cycle = fx.beats <= 0 ? 1.0 : fx.beats;
  final offset = count > 1 ? fx.spread * index / count : 0.0;
  final f = _frac(beat / cycle + offset);
  final span = fx.high - fx.low;
  final v = switch (fx.pattern) {
    LiveLevelPattern.solid => fx.high,
    LiveLevelPattern.breathe => fx.low + span * (0.5 - 0.5 * math.cos(2 * math.pi * f)),
    LiveLevelPattern.pulse => fx.low + span * (1 - f) * (1 - f),
    LiveLevelPattern.ramp => fx.low + span * f,
    LiveLevelPattern.chase => (count <= 0 || (beat / cycle).floor() % count == index) ? fx.high : fx.low,
  };
  return v.clamp(0.0, 1.0);
}

int _blend(int a, int b, double t) {
  int ch(int shift) {
    final x = (a >> shift) & 255;
    final y = (b >> shift) & 255;
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int _hsv(double hue) {
  final h = _frac(hue) * 6;
  final i = h.floor();
  final f = h - i;
  final q = ((1 - f) * 255).round();
  final t = (f * 255).round();
  final (r, g, b) = switch (i % 6) {
    0 => (255, t, 0),
    1 => (q, 255, 0),
    2 => (0, 255, t),
    3 => (0, q, 255),
    4 => (t, 0, 255),
    _ => (255, 0, q),
  };
  return (r << 16) | (g << 8) | b;
}

/// Fixture [index] of [count]'s colour (0xRRGGBB) at [beat] beats into the clip.
int colorValue(LiveColorFx fx, double beat, int index, int count) {
  final colors = fx.colors.isEmpty ? const [0xFFFFFF] : fx.colors;
  final step = fx.beats <= 0 ? 1.0 : fx.beats;
  final pos = beat / step;
  int pick(int i) => colors[((i % colors.length) + colors.length) % colors.length];
  int withFade(int i) {
    final a = pick(i);
    if (fx.fade <= 0 || colors.length < 2) return a;
    final f = _frac(pos);
    final start = 1 - fx.fade.clamp(0.0, 1.0);
    if (f <= start) return a;
    return _blend(a, pick(i + 1), (f - start) / (1 - start));
  }

  return switch (fx.pattern) {
    LiveColorPattern.solid => colors.first,
    LiveColorPattern.step => withFade(pos.floor()),
    LiveColorPattern.chase => withFade(pos.floor() + index),
    LiveColorPattern.alternate => pick(pos.floor() + index),
    LiveColorPattern.rainbow => _hsv(pos + (count > 0 ? index / count : 0)),
  };
}

/// The value that opens a strobe/shutter channel, from its capabilities:
/// a slot labelled open/on, else the first non-off slot. Null when the
/// profile doesn't say.
int? shutterOpenValue(List<ChannelCapability> caps) {
  for (final c in caps) {
    final label = c.label.toLowerCase();
    if (c.kind != CapabilityKind.range && (label.contains('open') || label == 'on' || label.contains('shutter on'))) {
      return c.pickValue;
    }
  }
  return null;
}

/// A strobe channel value for [amount] (0..1, slow → fast): inside the
/// range labelled strobe when the profile has one, else the whole channel.
int strobeValue(List<ChannelCapability> caps, double amount) {
  final a = amount.clamp(0.0, 1.0);
  for (final c in caps) {
    if (c.kind == CapabilityKind.range && c.label.toLowerCase().contains('strobe')) {
      return (c.min + (c.max - c.min) * a).round();
    }
  }
  return (a * 255).round();
}

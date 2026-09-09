import 'dart:async';
import 'dart:math';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/universe_config.dart';
import '../artnet/artnet_service.dart';

class _Instant {
  final Scene scene;
  final Duration hold;
  final Duration fade;

  const _Instant({required this.scene, required this.hold, required this.fade});
}

class _FadeTarget {
  final UniverseConfig universe;
  final int startChannel;
  final List<int> from;
  final List<int> to;

  const _FadeTarget({
    required this.universe,
    required this.startChannel,
    required this.from,
    required this.to,
  });
}

/// The minimum time a step is ever allowed to hold for, even if the user
/// dials Hold Time down to 0 — without this floor, a 0s hold with 0s fade
/// never awaits a real (timer-based) delay, which starves the event loop
/// solid (freezing the whole app) and floods the node with back-to-back
/// packets as fast as the CPU can issue them.
const _minStepDuration = Duration(milliseconds: 15);

/// How a beat-synced chase maps beats to steps.
enum BeatRate {
  /// One step every second beat — for looks that read better half speed.
  half,

  /// One step per beat.
  normal,

  /// Two steps per beat: one on the beat, one halfway to the next, timed
  /// off the last measured interval.
  doubled;

  String get label => switch (this) {
    BeatRate.half => '½×',
    BeatRate.normal => '1×',
    BeatRate.doubled => '2×',
  };
}

/// Drives a [Chase] (or a single [Bank] treated as one) in real time.
///
/// A bank step is expanded into one instant per filled slot — playing a
/// bank steps through its scenes just like a chase, instead of collapsing
/// them into one merged look. Each instant cross-fades in from the node's
/// last known channel values over its own `fade` duration, then holds for
/// `hold` — all channel writes for one tick of one universe go out as a
/// single Art-Net packet, never one packet per channel.
///
/// One instance is meant to be shared app-wide (see `playbackControllerProvider`)
/// so starting playback from anywhere always cleanly supersedes whatever was
/// already running, instead of two independent loops racing over the same
/// universes. Each [play] call gets its own generation token; a loop only
/// keeps running while its generation is still current, so even if [stop]
/// and a fresh [play] race each other, a stale loop can never come back to
/// life and run alongside the new one.
class ChasePlayer {
  bool _running = false;
  int _generation = 0;
  int _index = 0;
  bool _forward = true;
  final _random = Random();

  bool get isPlaying => _running;
  int get currentStepIndex => _index;

  bool _isCurrent(int generation) => _running && _generation == generation;

  List<_Instant> _flatten(Chase chase, List<Scene> scenes, List<Bank> banks) {
    final result = <_Instant>[];
    for (final step in chase.steps) {
      if (step.sceneId != null) {
        final matches = scenes.where((s) => s.id == step.sceneId);
        if (matches.isNotEmpty) {
          result.add(_Instant(scene: matches.first, hold: step.hold, fade: step.fade));
        }
      } else if (step.bankId != null) {
        final bankMatches = banks.where((b) => b.id == step.bankId);
        if (bankMatches.isEmpty) continue;
        for (final slotSceneId in bankMatches.first.sceneSlots) {
          if (slotSceneId == null) continue;
          final sceneMatches = scenes.where((s) => s.id == slotSceneId);
          if (sceneMatches.isEmpty) continue;
          result.add(_Instant(scene: sceneMatches.first, hold: step.hold, fade: step.fade));
        }
      }
    }
    return result;
  }

  Future<void> play({
    required Chase chase,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
    Stream<DateTime>? beatStream,
    BeatRate beatRate = BeatRate.normal,
    void Function(int instantIndex)? onStep,
  }) async {
    stop();
    final instants = _flatten(chase, scenes, banks);
    if (instants.isEmpty) return;

    final myGeneration = ++_generation;
    final useBeat = chase.beatSync && beatStream != null;
    _running = true;
    _index = chase.direction == ChaseDirection.random ? _random.nextInt(instants.length) : 0;
    _forward = true;

    // Beat bookkeeping for BeatRate.doubled: the off-beat step is timed off
    // however long the last two beats were apart, since the detector only
    // reports beats themselves.
    DateTime? previousBeatAt;
    var beatInterval = const Duration(milliseconds: 500);
    var stepIsOffBeat = false;

    while (_isCurrent(myGeneration)) {
      onStep?.call(_index);
      await _crossfadeTo(
        instants[_index].scene,
        fade: instants[_index].fade,
        service: service,
        patchedFixtures: patchedFixtures,
        universes: universes,
        generation: myGeneration,
      );
      if (!_isCurrent(myGeneration)) break;
      if (useBeat) {
        if (stepIsOffBeat) {
          await _holdFor(beatInterval ~/ 2, myGeneration);
          stepIsOffBeat = false;
        } else {
          final beatAt = await _waitForBeat(beatStream, myGeneration, beatRate == BeatRate.half ? 2 : 1);
          if (beatAt != null) {
            final measured = previousBeatAt == null ? null : beatAt.difference(previousBeatAt);
            // Ignore a gap that means the music stopped rather than a tempo
            // this slow, so the off-beat step never strands mid-fade.
            if (measured != null && measured > Duration.zero && measured <= const Duration(seconds: 2)) {
              beatInterval = measured;
            }
            previousBeatAt = beatAt;
          }
          stepIsOffBeat = beatRate == BeatRate.doubled;
        }
      } else {
        await _holdFor(instants[_index].hold, myGeneration);
      }
      if (!_isCurrent(myGeneration)) break;
      _advance(instants.length, chase.direction);
    }
  }

  /// Waits for the next beat to step on, returning when it landed — or null
  /// if playback was superseded first. [skip] > 1 waits out that many beats
  /// (2 for half time).
  Future<DateTime?> _waitForBeat(Stream<DateTime> beatStream, int generation, int skip) async {
    final completer = Completer<DateTime?>();
    var beatsSeen = 0;
    final subscription = beatStream.listen((beatAt) {
      if (++beatsSeen < skip) return;
      if (!completer.isCompleted) completer.complete(beatAt);
    });
    final safetyCheck = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isCurrent(generation) && !completer.isCompleted) completer.complete(null);
    });
    final beatAt = await completer.future;
    safetyCheck.cancel();
    await subscription.cancel();
    return beatAt;
  }

  Future<void> _crossfadeTo(
    Scene target, {
    required Duration fade,
    required ArtNetService service,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required int generation,
  }) async {
    final targets = <_FadeTarget>[];
    for (final entry in target.fixtureValues.entries) {
      final fixtureMatches = patchedFixtures.where((f) => f.id == entry.key);
      if (fixtureMatches.isEmpty) continue;
      final fixture = fixtureMatches.first;
      final universeMatches = universes.where((u) => u.id == fixture.universeId);
      if (universeMatches.isEmpty) continue;
      final universe = universeMatches.first;
      final to = entry.value;
      final from = [
        for (var i = 0; i < to.length; i++) service.getChannelValue(universe, fixture.startChannel + i),
      ];
      targets.add(_FadeTarget(universe: universe, startChannel: fixture.startChannel, from: from, to: to));
    }

    if (fade <= Duration.zero) {
      _writeStep(targets, 1.0, service);
      // Still yield one real event-loop tick — see `_minStepDuration`.
      await Future<void>.delayed(_minStepDuration);
      return;
    }

    const tickMs = 40;
    final tickCount = (fade.inMilliseconds / tickMs).ceil().clamp(1, 2000);
    for (var tick = 1; tick <= tickCount && _isCurrent(generation); tick++) {
      _writeStep(targets, tick / tickCount, service);
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
    }
  }

  void _writeStep(List<_FadeTarget> targets, double t, ArtNetService service) {
    final touched = <UniverseConfig>{};
    for (final target in targets) {
      for (var i = 0; i < target.to.length; i++) {
        final value = (target.from[i] + (target.to[i] - target.from[i]) * t).round();
        service.setChannel(target.universe, target.startChannel + i, value.clamp(0, 255), send: false);
      }
      touched.add(target.universe);
    }
    for (final universe in touched) {
      service.flush(universe);
    }
  }

  Future<void> _holdFor(Duration duration, int generation) async {
    final effective = duration < _minStepDuration ? _minStepDuration : duration;
    final end = DateTime.now().add(effective);
    while (_isCurrent(generation) && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }

  void _advance(int total, ChaseDirection direction) {
    switch (direction) {
      case ChaseDirection.forward:
        _index = (_index + 1) % total;
        break;
      case ChaseDirection.bounce:
        if (total == 1) break;
        if (_forward) {
          _index++;
          if (_index >= total - 1) {
            _index = total - 1;
            _forward = false;
          }
        } else {
          _index--;
          if (_index <= 0) {
            _index = 0;
            _forward = true;
          }
        }
        break;
      case ChaseDirection.random:
        _index = _random.nextInt(total);
        break;
    }
  }

  /// Ramps every channel on [universes] down to zero over [over] instead of
  /// snapping to black — so a show fades out gently rather than cutting.
  ///
  /// Runs under the same generation token as playback, so firing anything
  /// new mid-fade cleanly takes over instead of the two fighting.
  Future<void> fadeToBlack({
    required Duration over,
    required ArtNetService service,
    required List<UniverseConfig> universes,
  }) async {
    stop();
    if (over <= Duration.zero) {
      service.blackoutAll(universes);
      return;
    }
    final myGeneration = ++_generation;
    _running = true;
    const tickMs = 40;
    final tickCount = (over.inMilliseconds / tickMs).ceil().clamp(1, 2000);
    final startLevels = {
      for (final universe in universes)
        universe: [for (var channel = 0; channel < 512; channel++) service.getChannelValue(universe, channel)],
    };

    for (var tick = 1; tick <= tickCount && _isCurrent(myGeneration); tick++) {
      final remaining = 1 - tick / tickCount;
      for (final entry in startLevels.entries) {
        var touched = false;
        for (var channel = 0; channel < 512; channel++) {
          final from = entry.value[channel];
          if (from == 0) continue;
          service.setChannel(entry.key, channel, (from * remaining).round().clamp(0, 255), send: false);
          touched = true;
        }
        if (touched) service.flush(entry.key);
      }
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
    }

    if (!_isCurrent(myGeneration)) return;
    service.blackoutAll(universes);
    _running = false;
  }

  /// Stops playback immediately and invalidates any in-flight loop's
  /// generation, so a stale loop still unwinding (e.g. mid-fade-tick) can
  /// never mistake a subsequent [play] call's generation for its own and
  /// keep running alongside it.
  void stop() {
    _running = false;
    _generation++;
  }

  void dispose() => stop();
}

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

  /// The lit→dark release time to use instead of the usual zero, when this
  /// instant is the "dark" half of a Beat Flash bank running at
  /// [BeatRate.flash] and that bank has its own [Bank.flashFadeOutMs] set.
  /// Null everywhere else, which keeps the flash's attack (dark→lit) always
  /// instant.
  final Duration? flashFadeOut;

  /// From a Beat Flash bank: always plays at [BeatRate.flash] while beat
  /// synced, whatever the app-wide rate is set to. The rate is shared by
  /// every layer, so setting it to Flash for a flash bank on one layer used
  /// to make everything else running start stabbing along with it.
  final bool isFlash;

  /// The lit half of a Beat Flash bank's dark/lit pair — the step that
  /// only stays up for the flash length.
  final bool isFlashLit;

  const _Instant({
    required this.scene,
    required this.hold,
    required this.fade,
    this.flashFadeOut,
    this.isFlash = false,
    this.isFlashLit = false,
  });
}

class _FadeTarget {
  final UniverseConfig universe;
  final int startChannel;

  /// Channel offset (within the fixture) -> value, from and to. Only offsets
  /// the target scene actually specifies appear here — see [Scene.fixtureValues].
  final Map<int, int> from;
  final Map<int, int> to;

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
  doubled,

  /// A stab: step on the beat, then straight on to the next step after a
  /// fixed short time rather than half a beat.
  ///
  /// With a two-scene bank — lamps up, lamps out — that's one flash per
  /// beat whose length you set, instead of the square wave [doubled] gives
  /// (its off-step always lands at 50% duty, however fast the music is).
  /// Fades are forced off here: a flash with a fade isn't a flash.
  flash;

  String get label => switch (this) {
    BeatRate.half => '½×',
    BeatRate.normal => '1×',
    BeatRate.doubled => '2×',
    BeatRate.flash => 'Flash',
  };

  /// Whether this rate inserts a second step between beats.
  bool get hasOffBeatStep => this == doubled || this == flash;
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
  /// The layer this player writes for, or null for a player outside the
  /// layer system (tests, one-off previews). A layered player's writes go
  /// through [ArtNetService.setLayerChannel], so a layer started after it
  /// keeps the channels the two share, and [stop] hands its channels back.
  final String? layerId;

  ChasePlayer({this.layerId});

  bool _running = false;
  ArtNetService? _service;
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
        final bank = bankMatches.first;
        // A Beat Flash bank is always [dark, lit] pairs (see
        // `buildBeatFlashScenes`) — the even slot in each pair is the dark
        // one, which is where a configured release time applies.
        final slots = bank.sceneSlots;
        // The fixtures the flash actually lights. Its dark scene is built
        // for the whole rig, so once the lit one is trimmed to a few lamps
        // the dark one would still black out every other lamp on each beat
        // — the rest of the rig "flashing" along with it.
        final flashFixtures = !bank.isBeatFlash
            ? null
            : {
                for (var slot = 1; slot < slots.length; slot += 2)
                  ...?scenes.where((s) => s.id == slots[slot]).firstOrNull?.fixtureValues.keys,
              };
        for (var slot = 0; slot < slots.length; slot++) {
          final slotSceneId = slots[slot];
          if (slotSceneId == null) continue;
          final sceneMatches = scenes.where((s) => s.id == slotSceneId);
          if (sceneMatches.isEmpty) continue;
          final isDarkSlot = bank.isBeatFlash && slot.isEven;
          var scene = sceneMatches.first;
          if (isDarkSlot && flashFixtures != null && flashFixtures.isNotEmpty) {
            scene = scene.copyWith(fixtureValues: {
              for (final entry in scene.fixtureValues.entries)
                if (flashFixtures.contains(entry.key)) entry.key: entry.value,
            });
          }
          result.add(_Instant(
            isFlash: bank.isBeatFlash,
            isFlashLit: bank.isBeatFlash && slot.isOdd,
            scene: scene,
            hold: step.hold,
            fade: step.fade,
            flashFadeOut: isDarkSlot && bank.flashFadeOutMs > 0
                ? Duration(milliseconds: bank.flashFadeOutMs)
                : null,
          ));
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
    Duration? Function()? fadeOverride,
    Duration flashLength = const Duration(milliseconds: 80),
    // Both read per step when given, for the same reason the fade is:
    // changing the beat rate used to need a restart, so switching away from
    // Flash anywhere that doesn't restart (the control dock) left the chase
    // flashing on regardless.
    BeatRate Function()? liveBeatRate,
    Duration Function()? liveFlashLength,
    // The app-wide beat-sync switch, for a chase that follows it. Read per
    // step, so switching beat sync on or off lands on the running chase —
    // it used to be fixed at play() time, which left a chase started on
    // the beat frozen waiting for beats once beat sync was switched off.
    bool Function()? liveBeatSync,
    // The project's current banks and scenes, checked before every step: an
    // edit to one this chase plays — a Beat Flash bank's fade-out, a slot, a
    // scene's values — lands on the next step instead of only after the
    // chase is stopped and started again.
    List<Bank> Function()? liveBanks,
    List<Scene> Function()? liveScenes,
    // Makes this layer the newest one, winning the channels it shares with
    // other layers. Off for a restart that shouldn't jump the queue (a
    // Smart Program changing zone).
    bool claim = true,
  }) async {
    _halt();
    var instants = _flatten(chase, scenes, banks);
    var playedBanks = banks;
    var playedScenes = scenes;
    if (instants.isEmpty) {
      stop();
      return;
    }
    _service = service;
    final layer = layerId;
    if (layer != null) {
      if (claim) service.claimLayer(layer);
      // Channels the previous run held that this one never touches go back
      // to whichever layer wants them, instead of staying parked here.
      final keep = <String, Set<int>>{};
      for (final instant in instants) {
        for (final entry in instant.scene.fixtureValues.entries) {
          final fixture = patchedFixtures.where((f) => f.id == entry.key).firstOrNull;
          if (fixture == null) continue;
          final channels = keep.putIfAbsent(fixture.universeId, () => <int>{});
          for (final offset in entry.value.keys) {
            channels.add(fixture.startChannel + offset);
          }
        }
      }
      service.releaseLayer(layer, keep: keep);
    }

    final myGeneration = ++_generation;
    bool beatSynced() => beatStream != null && (liveBeatSync?.call() ?? chase.beatSync);
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
      final banksNow = liveBanks?.call() ?? playedBanks;
      final scenesNow = liveScenes?.call() ?? playedScenes;
      // Lists are replaced, never mutated, on every edit — so identity says
      // whether anything changed since the last step.
      if (!identical(banksNow, playedBanks) || !identical(scenesNow, playedScenes)) {
        playedBanks = banksNow;
        playedScenes = scenesNow;
        final refreshed = _flatten(chase, scenesNow, banksNow);
        if (refreshed.isNotEmpty) {
          instants = refreshed;
          if (_index >= instants.length) _index = 0;
        }
      }
      final useBeat = beatSynced();
      if (!useBeat) stepIsOffBeat = false;
      final instant = instants[_index];
      final rate = instant.isFlash ? BeatRate.flash : (liveBeatRate?.call() ?? beatRate);
      onStep?.call(_index);
      await _crossfadeTo(
        instant.scene,
        // Asked per step rather than baked in at play() time, so auto-fade
        // can track the tempo without restarting the chase — restarting is
        // what used to make a beat-synced bank stutter. Flash overrides
        // everything: a stab that fades in is just a short fade — except a
        // Beat Flash bank's own configured release, which only ever applies
        // going into its dark step (the attack in is always instant). A
        // Beat Flash bank is a flash on the timers too, not just the beat.
        fade: instant.isFlash || (useBeat && rate == BeatRate.flash)
            ? (instant.flashFadeOut ?? Duration.zero)
            : fadeOverride?.call() ?? instant.fade,
        service: service,
        patchedFixtures: patchedFixtures,
        universes: universes,
        generation: myGeneration,
      );
      if (!_isCurrent(myGeneration)) break;
      if (useBeat) {
        // A Beat Flash step knows its own part — dark waits for the beat,
        // lit is the short stab after it. Counting on/off steps instead goes
        // out of phase as soon as a chase mixes in anything else (a 2× bank
        // before it, Random order), and then the dark step flashes while
        // the lit one holds a whole beat — no flash at all.
        final holdShort = instant.isFlash ? instant.isFlashLit : stepIsOffBeat;
        if (holdShort) {
          // Flash holds the lit step for a fixed short time; doubled splits
          // the measured beat in half.
          await _holdFor(
            rate == BeatRate.flash ? (liveFlashLength?.call() ?? flashLength) : beatInterval ~/ 2,
            myGeneration,
          );
          stepIsOffBeat = false;
        } else {
          final beatAt = await _waitForBeat(beatStream!, myGeneration, rate == BeatRate.half ? 2 : 1, beatSynced);
          if (beatAt != null) {
            final measured = previousBeatAt == null ? null : beatAt.difference(previousBeatAt);
            // Ignore a gap that means the music stopped rather than a tempo
            // this slow, so the off-beat step never strands mid-fade.
            if (measured != null && measured > Duration.zero && measured <= const Duration(seconds: 2)) {
              beatInterval = measured;
            }
            previousBeatAt = beatAt;
          }
          stepIsOffBeat = !instant.isFlash && rate.hasOffBeatStep;
        }
      } else {
        await _holdFor(
          instant.isFlashLit ? (liveFlashLength?.call() ?? flashLength) : instant.hold,
          myGeneration,
        );
      }
      if (!_isCurrent(myGeneration)) break;
      _advance(instants.length, chase.direction);
    }
  }

  /// Waits for the next beat to step on, returning when it landed — or null
  /// if playback was superseded first. [skip] > 1 waits out that many beats
  /// (2 for half time).
  Future<DateTime?> _waitForBeat(
    Stream<DateTime> beatStream,
    int generation,
    int skip,
    bool Function() stillSynced,
  ) async {
    final completer = Completer<DateTime?>();
    var beatsSeen = 0;
    final subscription = beatStream.listen((beatAt) {
      if (++beatsSeen < skip) return;
      if (!completer.isCompleted) completer.complete(beatAt);
    });
    final safetyCheck = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if ((!_isCurrent(generation) || !stillSynced()) && !completer.isCompleted) completer.complete(null);
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
      final from = {
        for (final offset in to.keys) offset: service.getChannelValue(universe, fixture.startChannel + offset),
      };
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
      for (final offset in target.to.keys) {
        final from = target.from[offset] ?? 0;
        final to = target.to[offset]!;
        final value = (from + (to - from) * t).round();
        _write(service, target.universe, target.startChannel + offset, value);
      }
      touched.add(target.universe);
    }
    for (final universe in touched) {
      service.flush(universe);
    }
  }

  void _write(ArtNetService service, UniverseConfig universe, int channel, int value) {
    final layer = layerId;
    if (layer == null) {
      service.setChannel(universe, channel, value.clamp(0, 255), send: false);
    } else {
      service.setLayerChannel(universe, channel, value, layer);
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
    _halt();
    _service = service;
    if (over <= Duration.zero) {
      _blackout(service, universes);
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
          _write(service, entry.key, channel, (from * remaining).round());
          touched = true;
        }
        if (touched) service.flush(entry.key);
      }
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
    }

    if (!_isCurrent(myGeneration)) return;
    _blackout(service, universes);
    _running = false;
  }

  /// Everything this player may write to, to zero. A layered player leaves
  /// alone the channels a newer layer holds — blacking the whole rig out
  /// from under a layer that's still playing isn't its call.
  void _blackout(ArtNetService service, List<UniverseConfig> universes) {
    if (layerId == null) {
      service.blackoutAll(universes);
      return;
    }
    for (final universe in universes) {
      for (var channel = 0; channel < 512; channel++) {
        _write(service, universe, channel, 0);
      }
      service.flush(universe);
    }
  }

  /// Stops playback immediately and invalidates any in-flight loop's
  /// generation, so a stale loop still unwinding (e.g. mid-fade-tick) can
  /// never mistake a subsequent [play] call's generation for its own and
  /// keep running alongside it.
  void stop() {
    _halt();
    final layer = layerId;
    if (layer != null) _service?.releaseLayer(layer);
  }

  /// Ends the running loop but keeps this layer's channels — for handing
  /// straight over to the next run without the rig dropping in between.
  void _halt() {
    _running = false;
    _generation++;
  }

  void dispose() => stop();
}

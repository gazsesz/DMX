import 'dart:async';
import 'dart:math';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/fixture_channel.dart';
import '../../models/fixture_group.dart';
import '../../models/movement_fx.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/stage_plan.dart';
import '../../models/universe_config.dart';
import '../artnet/artnet_service.dart';
import '../movement/movement_engine.dart';
import 'dimmer_dropout.dart';

class _Instant {
  /// What to fade to. Null for a Movement FX step, which has [fx] instead.
  final Scene? scene;

  /// A Movement FX bank step: the path to run for [hold] (forever when the
  /// hold is zero), gliding onto it over [fade]. [bankId] lets the running
  /// path pick up edits to the bank live.
  final MovementFx? fx;
  final String? bankId;
  final bool restartFx;
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

  /// A bank step with its own timing ([Bank.slotTimings]): its fade is kept
  /// even while the dock's auto-fade would otherwise replace it.
  final bool ownTiming;

  const _Instant({
    this.scene,
    this.fx,
    this.bankId,
    this.restartFx = false,
    required this.hold,
    required this.fade,
    this.flashFadeOut,
    this.isFlash = false,
    this.isFlashLit = false,
    this.ownTiming = false,
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

  /// Told what dimmer dropout the chase now playing on [layerId] asks for, or
  /// null once it stops — see [DimmerDropoutController.setChaseDropout].
  final void Function(String layerId, DropoutSettings? settings)? onDropout;

  ChasePlayer({this.layerId, this.onDropout});

  bool _disposed = false;

  void _setDropout(DropoutSettings? settings) {
    final layer = layerId;
    if (layer != null && !_disposed) onDropout?.call(layer, settings);
  }

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
        if (bank.fx != null) {
          result.add(_Instant(
            fx: bank.fx,
            bankId: bank.id,
            restartFx: step.fxRestart,
            hold: step.hold,
            fade: step.fade,
          ));
          continue;
        }
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
          // A step's own timing beats the bank's and the dock's. A Beat
          // Flash bank's steps are timed by the flash itself, so it has none.
          final own = bank.isBeatFlash ? null : bank.timingAt(slot);
          result.add(_Instant(
            isFlash: bank.isBeatFlash,
            isFlashLit: bank.isBeatFlash && slot.isOdd,
            scene: scene,
            hold: own?.hold ?? step.hold,
            fade: own?.fade ?? step.fade,
            ownTiming: own != null,
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
    // Whether beats are actually arriving (the mic or MIDI clock is on),
    // whatever this chase's own beat sync says. A Beat Flash bank goes by
    // this rather than the chase's switch: dropped into a chase it flashes
    // on the beat without the chase having to be set up for it first.
    bool Function()? liveBeatAvailable,
    // How long a Beat Flash bank's dark step lasts when there are no beats
    // to wait for — one beat at the show's tempo, instead of the chase
    // step's hold, which had to be dragged to zero for the flash to show.
    Duration Function()? liveFlashGap,
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
    // What Movement FX banks need beyond the patch: the stage plan (for
    // paths drawn on the floor) and the fixture groups they can be limited
    // to. Read as the effect runs, so an edit lands straight away.
    StagePlan Function()? liveStage,
    List<FixtureGroup> Function()? liveGroups,
    // The dock's current Hold and Fade, for a Movement FX look that follows them.
    ({Duration hold, Duration fade}) Function()? liveDockTiming,
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
    _setDropout(chase.dropout);
    final layer = layerId;
    if (layer != null) {
      if (claim) service.claimLayer(layer);
      // Channels the previous run held that this one never touches go back
      // to whichever layer wants them, instead of staying parked here.
      final keep = <String, Set<int>>{};
      for (final instant in instants) {
        final instantFx = instant.fx;
        if (instantFx != null) {
          for (final head in movementHeads(instantFx, patchedFixtures, liveGroups?.call() ?? const [])) {
            final channels = keep.putIfAbsent(head.fixture.universeId, () => <int>{});
            for (final offset in head.offsets) {
              channels.add(head.fixture.startChannel + offset);
            }
          }
          final heads = movementHeads(instantFx, patchedFixtures, liveGroups?.call() ?? const []);
          for (final look in _lookInstants(instantFx, heads, banks, scenes, patchedFixtures)) {
            for (final entry in look.scene!.fixtureValues.entries) {
              final fixture = patchedFixtures.where((f) => f.id == entry.key).firstOrNull;
              if (fixture == null) continue;
              final channels = keep.putIfAbsent(fixture.universeId, () => <int>{});
              for (final offset in entry.value.keys) {
                channels.add(fixture.startChannel + offset);
              }
            }
          }
        }
        for (final entry in instant.scene?.fixtureValues.entries ?? const <MapEntry<String, Map<int, int>>>[]) {
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
    bool flashOnBeat() => beatStream != null && (liveBeatAvailable?.call() ?? beatSynced());
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
      final instant = instants[_index];
      final useBeat = instant.isFlash ? flashOnBeat() : beatSynced();
      if (!useBeat) stepIsOffBeat = false;
      final rate = instant.isFlash ? BeatRate.flash : (liveBeatRate?.call() ?? beatRate);
      onStep?.call(_index);
      if (instant.fx != null) {
        await _runFx(
          instant,
          service: service,
          patchedFixtures: patchedFixtures,
          universes: universes,
          generation: myGeneration,
          beatStream: beatStream,
          banks: playedBanks,
          scenes: playedScenes,
          liveBanks: liveBanks,
          liveScenes: liveScenes,
          liveStage: liveStage,
          liveGroups: liveGroups,
          liveDockTiming: liveDockTiming,
          liveBeatSync: instant.isFlash ? flashOnBeat : beatSynced,
          liveBeatRate: liveBeatRate ?? () => beatRate,
        );
        if (!_isCurrent(myGeneration)) break;
        _advance(instants.length, chase.direction);
        continue;
      }
      await _crossfadeTo(
        instant.scene!,
        // Asked per step rather than baked in at play() time, so auto-fade
        // can track the tempo without restarting the chase — restarting is
        // what used to make a beat-synced bank stutter. Flash overrides
        // everything: a stab that fades in is just a short fade — except a
        // Beat Flash bank's own configured release, which only ever applies
        // going into its dark step (the attack in is always instant). A
        // Beat Flash bank is a flash on the timers too, not just the beat.
        fade: instant.isFlash || (useBeat && rate == BeatRate.flash)
            ? (instant.flashFadeOut ?? Duration.zero)
            : instant.ownTiming
                ? instant.fade
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
          final beatAt = await _waitForBeat(
            beatStream!,
            myGeneration,
            rate == BeatRate.half ? 2 : 1,
            instant.isFlash ? flashOnBeat : beatSynced,
          );
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
          instant.isFlashLit
              ? (liveFlashLength?.call() ?? flashLength)
              : instant.isFlash
                  ? (liveFlashGap?.call() ?? instant.hold)
                  : instant.hold,
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

  /// Where the movement path has got to. Kept across steps and restarts of
  /// the player, so one FX step flows into the next (and a Smart Program
  /// changing zone doesn't throw the heads back to the start of a lap).
  final _fxClock = MovementClock();
  static const _fxTick = Duration(milliseconds: 25);

  /// The scenes of an FX bank's look, as played next to the path: its pan and
  /// tilt are dropped for the heads the path drives, so the two never fight.
  List<_Instant> _lookInstants(
    MovementFx fx,
    List<MovementHead> heads,
    List<Bank> banks,
    List<Scene> scenes,
    List<PatchedFixture> patchedFixtures,
  ) {
    final bankId = fx.lookBankId;
    if (bankId == null || banks.any((b) => b.id == bankId && b.isMovementFx)) return const [];
    final flat = _flatten(
      Chase(
        id: 'look',
        name: 'look',
        steps: [
          ChaseStep(
            bankId: bankId,
            hold: Duration(milliseconds: fx.lookHoldMs),
            fade: Duration(milliseconds: fx.lookFadeMs),
          ),
        ],
      ),
      scenes,
      banks,
    );
    final moving = {for (final head in heads) head.fixture.id};
    return [
      for (final instant in flat)
        _Instant(
          scene: _withoutPosition(instant.scene!, moving, patchedFixtures),
          hold: instant.hold,
          fade: instant.fade,
          ownTiming: instant.ownTiming,
        ),
    ];
  }

  static Scene _withoutPosition(Scene scene, Set<String> movingIds, List<PatchedFixture> patchedFixtures) {
    return scene.copyWith(fixtureValues: {
      for (final entry in scene.fixtureValues.entries)
        entry.key: movingIds.contains(entry.key)
            ? () {
                final fixture = patchedFixtures.where((f) => f.id == entry.key).firstOrNull;
                final position = {
                  for (final channel in fixture?.profile.channels ?? const <FixtureChannel>[])
                    if (channel.function.isPanTilt) channel.offset,
                };
                return {
                  for (final value in entry.value.entries)
                    if (!position.contains(value.key)) value.key: value.value,
                };
              }()
            : entry.value,
    });
  }

  /// Runs a Movement FX step: writes the heads' pan/tilt every [_fxTick]
  /// for the step's hold (forever when it is zero), after gliding onto the
  /// path from wherever the heads are over the step's fade. Only the pan/tilt
  /// channels are touched by the path; the optional look (colours, gobo…)
  /// steps through its scenes alongside, on the dock's Hold/Fade and beat
  /// sync or on its own timing.
  Future<void> _runFx(
    _Instant instant, {
    required ArtNetService service,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required int generation,
    required List<Bank> banks,
    required List<Scene> scenes,
    Stream<DateTime>? beatStream,
    List<Bank> Function()? liveBanks,
    List<Scene> Function()? liveScenes,
    StagePlan Function()? liveStage,
    List<FixtureGroup> Function()? liveGroups,
    ({Duration hold, Duration fade}) Function()? liveDockTiming,
    bool Function()? liveBeatSync,
    BeatRate Function()? liveBeatRate,
  }) async {
    var fx = instant.fx!;
    if (instant.restartFx) _fxClock.phase = 0;
    List<MovementHead> headsFor(MovementFx effect) =>
        movementHeads(effect, patchedFixtures, liveGroups?.call() ?? const []);
    var heads = headsFor(fx);
    var look = _lookInstants(fx, heads, banks, scenes, patchedFixtures);
    final universeOf = {for (final universe in universes) universe.id: universe};

    int read(MovementHead head, UniverseConfig universe, int offset) =>
        service.getChannelValue(universe, head.fixture.startChannel + offset);
    PanTilt current(MovementHead head, UniverseConfig universe) => PanTilt.fromChannels(
      pan: read(head, universe, head.panOffset),
      panFine: head.panFineOffset == null ? 0 : read(head, universe, head.panFineOffset!),
      tilt: read(head, universe, head.tiltOffset),
      tiltFine: head.tiltFineOffset == null ? 0 : read(head, universe, head.tiltFineOffset!),
    );

    // The look: one fade-then-hold per scene, in order, round and round.
    var lookIndex = 0;
    var lookStepAt = Duration.zero;
    var lookNeedsStart = true;
    var lookSettled = false;
    var lookFade = Duration.zero;
    var lookHold = Duration.zero;
    var lookTargets = <({UniverseConfig universe, int channel, int from, int to})>[];
    var beatsSeen = 0;
    var lookAdvance = false;

    DateTime? lastBeat;
    final beatSub = beatStream?.listen((at) {
      final gap = lastBeat == null ? null : at.difference(lastBeat!);
      lastBeat = at;
      _fxClock.onBeat(fx, interval: gap);
      beatsSeen++;
      final skip = (liveBeatRate?.call() ?? BeatRate.normal) == BeatRate.half ? 2 : 1;
      if (beatsSeen >= skip) {
        beatsSeen = 0;
        lookAdvance = true;
      }
    });

    final hold = instant.hold <= Duration.zero ? null : (instant.hold < _minStepDuration ? _minStepDuration : instant.hold);
    final glideUs = instant.fade.inMicroseconds;
    final from = <String, PanTilt>{};
    var previous = <String, PanTilt>{};
    var banksNow = banks;
    var scenesNow = scenes;
    final clock = Stopwatch()..start();
    var last = Duration.zero;
    try {
      while (_isCurrent(generation)) {
        final now = clock.elapsed;
        if (hold != null && now >= hold) break;

        // Live edits: the bank's path and look, or the scenes the look plays.
        final newBanks = liveBanks?.call() ?? banksNow;
        final newScenes = liveScenes?.call() ?? scenesNow;
        final liveFx = instant.bankId == null ? null : newBanks.where((b) => b.id == instant.bankId).firstOrNull?.fx;
        final changed = (liveFx != null && liveFx != fx) ||
            !identical(newBanks, banksNow) ||
            !identical(newScenes, scenesNow);
        if (changed) {
          if (liveFx != null) fx = liveFx;
          banksNow = newBanks;
          scenesNow = newScenes;
          heads = headsFor(fx);
          look = _lookInstants(fx, heads, banksNow, scenesNow, patchedFixtures);
          if (lookIndex >= look.length) lookIndex = 0;
          lookNeedsStart = true;
        }

        _fxClock.tick(now - last, fx);
        last = now;
        final frame = movementFrame(fx, heads, _fxClock.phase, liveStage?.call() ?? const StagePlan(), previous: previous);
        final glide = glideUs <= 0 ? 1.0 : (now.inMicroseconds / glideUs).clamp(0.0, 1.0);
        final eased = glide * glide * (3 - 2 * glide);

        final touched = <UniverseConfig>{};
        final written = <String, PanTilt>{};
        for (final head in heads) {
          final universe = universeOf[head.fixture.universeId];
          final target = frame[head.fixture.id];
          if (universe == null || target == null) continue;
          final start = from.putIfAbsent(head.fixture.id, () => current(head, universe));
          final position = lerpPanTilt(start, target, eased);
          written[head.fixture.id] = position;
          final base = head.fixture.startChannel;
          _write(service, universe, base + head.panOffset, position.panCoarse);
          if (head.panFineOffset != null) _write(service, universe, base + head.panFineOffset!, position.panFine);
          _write(service, universe, base + head.tiltOffset, position.tiltCoarse);
          if (head.tiltFineOffset != null) _write(service, universe, base + head.tiltFineOffset!, position.tiltFine);
          touched.add(universe);
        }
        previous = written;

        if (look.isNotEmpty) {
          final step = look[lookIndex % look.length];
          final dock = liveDockTiming?.call();
          final ownClock = fx.lookOwnTiming || dock == null;
          final beatStepping = !ownClock && beatStream != null && (liveBeatSync?.call() ?? false);
          if (lookNeedsStart) {
            lookNeedsStart = false;
            lookSettled = false;
            lookAdvance = false;
            beatsSeen = 0;
            lookStepAt = now;
            lookFade = ownClock || step.ownTiming ? step.fade : dock.fade;
            lookHold = ownClock || step.ownTiming ? step.hold : dock.hold;
            lookTargets = [
              for (final entry in step.scene!.fixtureValues.entries)
                for (final value in entry.value.entries)
                  if (patchedFixtures.where((f) => f.id == entry.key).firstOrNull case final fixture?)
                    if (universeOf[fixture.universeId] case final universe?)
                      (
                        universe: universe,
                        channel: fixture.startChannel + value.key,
                        from: service.getChannelValue(universe, fixture.startChannel + value.key),
                        to: value.value,
                      ),
            ];
          }
          if (!lookSettled) {
            final t = lookFade <= Duration.zero
                ? 1.0
                : ((now - lookStepAt).inMicroseconds / lookFade.inMicroseconds).clamp(0.0, 1.0);
            for (final target in lookTargets) {
              _write(service, target.universe, target.channel, (target.from + (target.to - target.from) * t).round());
              touched.add(target.universe);
            }
            if (t >= 1) lookSettled = true;
          }
          if (look.length > 1) {
            final due = beatStepping ? lookAdvance : now - lookStepAt >= lookFade + lookHold;
            if (due) {
              lookIndex = (lookIndex + 1) % look.length;
              lookNeedsStart = true;
            }
          }
        }

        for (final universe in touched) {
          service.flush(universe);
        }
        await Future<void>.delayed(_fxTick);
      }
    } finally {
      await beatSub?.cancel();
    }
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
    final tickCount = (fade.inMilliseconds / tickMs).ceil().clamp(1, 3000);
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
    // Channels to leave alone (another layer's running move, say).
    bool Function(UniverseConfig universe, int channel)? keep,
  }) async {
    _halt();
    _service = service;
    _setDropout(null);
    if (over <= Duration.zero) {
      _blackout(service, universes, keep);
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
          if (from == 0 || (keep?.call(entry.key, channel) ?? false)) continue;
          _write(service, entry.key, channel, (from * remaining).round());
          touched = true;
        }
        if (touched) service.flush(entry.key);
      }
      await Future<void>.delayed(const Duration(milliseconds: tickMs));
    }

    if (!_isCurrent(myGeneration)) return;
    _blackout(service, universes, keep);
    _running = false;
  }

  /// Everything this player may write to, to zero. A layered player leaves
  /// alone the channels a newer layer holds — blacking the whole rig out
  /// from under a layer that's still playing isn't its call.
  void _blackout(ArtNetService service, List<UniverseConfig> universes, [bool Function(UniverseConfig, int)? keep]) {
    if (layerId == null) {
      service.blackoutAll(universes);
      return;
    }
    for (final universe in universes) {
      for (var channel = 0; channel < 512; channel++) {
        if (keep?.call(universe, channel) ?? false) continue;
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
    _setDropout(null);
  }

  /// Ends the running loop but keeps this layer's channels — for handing
  /// straight over to the next run without the rig dropping in between.
  void _halt() {
    _running = false;
    _generation++;
  }

  void dispose() {
    // Stopping tells the dropout controller; that can't be read any more while
    // the provider container is going down.
    _disposed = true;
    stop();
  }
}

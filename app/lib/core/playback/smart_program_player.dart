import 'dart:async';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/smart_program.dart';
import '../../models/universe_config.dart';
import '../artnet/artnet_service.dart';
import '../audio/beat_source.dart';
import '../audio/tempo_estimator.dart';
import 'auto_fade_guard.dart';
import 'chase_player.dart';

export '../../models/smart_program.dart' show SmartProgramZone;

class SmartProgramStatus {
  final SmartProgramZone zone;
  final double? liveBpm;

  /// True while no beat has been heard for a while — the chase is blacked
  /// out and paused rather than stepping blind without any real tempo to
  /// follow. Resumes automatically (from the base zone) once beats return.
  final bool isSilent;

  const SmartProgramStatus({required this.zone, this.liveBpm, this.isSilent = false});
}

/// Drives a [SmartProgram]: watches the live beat tempo and, as the song
/// speeds up or slows down, hands every layer the program drives over to
/// that layer's own base/faster/slower target — one tempo reading, one
/// zone, but each layer playing its own thing in it. A switch only happens
/// once the new tempo has held for that direction's configured duration, so
/// a single early/late beat doesn't cause flicker.
class SmartProgramPlayer {
  /// The player for a layer id — each layer the program drives gets its own,
  /// the same one that layer uses for everything else.
  final ChasePlayer Function(String layerId) playerFor;
  final BeatSource beatService;

  /// What actually drives [_onBeat] and an embedded chase/bank's own beat
  /// sync (below) — the raw source by default, or a [BeatPredictor]'s
  /// stream when the caller wants missed beats filled in. Kept separate
  /// from [beatService] because that one still owns starting/stopping the
  /// source itself; a predictor only ever sits in front of it, never
  /// replaces it.
  final Stream<DateTime> beatEvents;

  /// The app-wide beat-sync switch, and the rate it's set to — read live
  /// rather than captured, so flipping either from the dock lands on the
  /// running program.
  final bool Function() beatSyncEnabled;
  final BeatRate Function() beatRate;
  final Duration Function() flashLength;

  /// The app-wide auto-fade switch, read and (temporarily) written — see
  /// [_updateAutoFadeSuppression]. Defaults to a no-op pair so tests and
  /// callers that don't care about this can ignore it entirely.
  final bool Function() isAutoFadeOn;
  final void Function(bool) setAutoFade;

  SmartProgramPlayer({
    required this.playerFor,
    required this.beatService,
    Stream<DateTime>? beatEvents,
    bool Function()? beatSyncEnabled,
    BeatRate Function()? beatRate,
    Duration Function()? flashLength,
    bool Function()? isAutoFadeOn,
    void Function(bool)? setAutoFade,
  })  : beatEvents = beatEvents ?? beatService.beatEvents,
        beatSyncEnabled = beatSyncEnabled ?? (() => false),
        beatRate = beatRate ?? (() => BeatRate.normal),
        flashLength = flashLength ?? (() => const Duration(milliseconds: 80)),
        isAutoFadeOn = isAutoFadeOn ?? (() => false),
        setAutoFade = setAutoFade ?? ((_) {});

  StreamSubscription<DateTime>? _beatSub;
  Timer? _confirmTimer;
  Timer? _silenceTimer;
  final List<DateTime> _beatTimes = [];
  SmartProgramZone _pendingZone = SmartProgramZone.base;
  SmartProgramZone _confirmedZone = SmartProgramZone.base;
  SmartProgram? _program;
  bool _isSilent = false;
  final _autoFadeGuard = AutoFadeGuard();

  /// Layers taken back for something else mid-run (a bank fired onto one
  /// of them, a Stop on just that layer) — the program leaves them alone
  /// until it's started again.
  final Set<String> _released = {};

  /// How long to wait without a single beat before assuming the music has
  /// stopped (rather than just being between two real beats of a slow song
  /// — even 40 BPM is a beat every 1.5s, so this leaves a wide margin).
  static const _silenceTimeout = Duration(seconds: 4);

  final _statusController = StreamController<SmartProgramStatus>.broadcast();
  Stream<SmartProgramStatus> get statusStream => _statusController.stream;

  bool get isRunning => _program != null;
  String? get activeProgramId => _program?.id;
  SmartProgramZone get currentZone => _confirmedZone;

  /// The layer ids this program is playing on right now.
  List<String> get drivenLayerIds {
    final program = _program;
    if (program == null) return const [];
    return [
      for (final l in program.drivenLayers)
        if (!_released.contains(l.layerId)) l.layerId,
    ];
  }

  bool drives(String layerId) => drivenLayerIds.contains(layerId);

  /// Gives [layerId] back: its player is stopped and the program stops
  /// handing it zones. Returns true when that was the last layer, in which
  /// case the whole program has been stopped too.
  bool releaseLayer(String layerId) {
    if (!drives(layerId)) return false;
    _released.add(layerId);
    playerFor(layerId).stop();
    if (drivenLayerIds.isEmpty) {
      stop();
      return true;
    }
    return false;
  }

  /// Starts [program]. Returns false if the microphone couldn't be opened.
  Future<bool> start({
    required SmartProgram program,
    required List<Chase> chases,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
  }) async {
    stop();
    final started = await beatService.start();
    if (!started) return false;

    _program = program;
    _released.clear();
    _beatTimes.clear();
    _pendingZone = SmartProgramZone.base;
    _confirmedZone = SmartProgramZone.base;
    _isSilent = false;
    // Starting the program is what makes its layers the newest; its own
    // zone changes later don't, so a bank fired over it afterwards keeps
    // the lamps it took.
    for (final layer in program.drivenLayers) {
      service.claimLayer(layer.layerId);
    }
    _playZone(
      SmartProgramZone.base,
      chases: chases,
      scenes: scenes,
      banks: banks,
      patchedFixtures: patchedFixtures,
      universes: universes,
      service: service,
    );
    _statusController.add(const SmartProgramStatus(zone: SmartProgramZone.base));
    _resetSilenceTimer(service: service, universes: universes);

    _beatSub = beatEvents.listen((now) {
      _onBeat(
        now,
        chases: chases,
        scenes: scenes,
        banks: banks,
        patchedFixtures: patchedFixtures,
        universes: universes,
        service: service,
      );
    });
    return true;
  }

  /// Applies an edited version of the program that's already running.
  ///
  /// Without this, saving a Smart Program changed nothing until you stopped
  /// and restarted it: [start] captures the program by value, so the runner
  /// kept driving the old thresholds, targets and fades while the editor
  /// showed the new ones. Now a save lands on the running show.
  ///
  /// Playback is only re-triggered when what the current zone plays on some
  /// layer — its target, fade or pace — actually changed; thresholds and
  /// hold times take effect on the next beat by themselves.
  void updateProgram(
    SmartProgram program, {
    required List<Chase> chases,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
  }) {
    final current = _program;
    if (current == null || current.id != program.id) return;
    final zone = _confirmedZone;
    final layerIds = {for (final l in current.layers) l.layerId, for (final l in program.layers) l.layerId};
    final targetChanged = layerIds.any(
      (id) => current.targetsFor(id).effective(zone) != program.targetsFor(id).effective(zone),
    );
    final fadeChanged = _fadeOf(current, zone) != _fadeOf(program, zone);
    final holdChanged = _zoneHold(current, zone) != _zoneHold(program, zone);
    _program = program;
    if (_isSilent) return;
    if (!targetChanged && !fadeChanged && !holdChanged) return;
    _playZone(
      zone,
      chases: chases,
      scenes: scenes,
      banks: banks,
      patchedFixtures: patchedFixtures,
      universes: universes,
      service: service,
    );
  }

  /// Re-fires the zone that's playing right now, without waiting for a
  /// tempo change to hand over.
  ///
  /// Whether a chase steps on beats is settled when it's fired, so arming
  /// or disarming beat sync mid-show has to re-fire the current zone or the
  /// switch does nothing until the music crosses a threshold.
  void replayCurrentZone({
    required List<Chase> chases,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
  }) {
    if (_program == null || _isSilent) return;
    _playZone(
      _confirmedZone,
      chases: chases,
      scenes: scenes,
      banks: banks,
      patchedFixtures: patchedFixtures,
      universes: universes,
      service: service,
    );
  }

  static Duration _fadeOf(SmartProgram program, SmartProgramZone zone) => switch (zone) {
    SmartProgramZone.base => program.baseFade,
    SmartProgramZone.faster => program.fasterFade,
    SmartProgramZone.slower => program.slowerFade,
  };

  void _resetSilenceTimer({required ArtNetService service, required List<UniverseConfig> universes}) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () => _enterSilence(service: service, universes: universes));
  }

  /// No beat has arrived for [_silenceTimeout] — the music has presumably
  /// stopped (or was never there). Blacks out and stops stepping instead of
  /// looping the base chase forever with nothing real driving it; a fresh
  /// beat later restarts cleanly.
  void _enterSilence({required ArtNetService service, required List<UniverseConfig> universes}) {
    final program = _program;
    if (program == null || _isSilent) return;
    _isSilent = true;
    _confirmTimer?.cancel();
    final layerIds = drivenLayerIds;
    if (layerIds.isEmpty) return;
    // One fade-out covers the whole rig: every other driven layer stops
    // first, and the first one dies out gently over the program's blackout
    // fade instead of cutting to black. `fadeToBlack` yields to anything
    // fired mid-fade.
    for (final id in layerIds.skip(1)) {
      playerFor(id).stop();
    }
    playerFor(layerIds.first).fadeToBlack(over: program.blackoutFade, service: service, universes: universes);
    _statusController.add(SmartProgramStatus(zone: _confirmedZone, isSilent: true));
  }

  void _onBeat(
    DateTime now, {
    required List<Chase> chases,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
  }) {
    final program = _program;
    if (program == null) return;

    _resetSilenceTimer(service: service, universes: universes);
    if (_isSilent) {
      // Music is back after a silent stretch. Come up on the *slower* zone
      // rather than the base one: a single beat says nothing about tempo
      // yet, and easing back in reads far better than slamming into a fast
      // look. The next few beats reclassify it properly anyway.
      _isSilent = false;
      _beatTimes.clear();
      _pendingZone = SmartProgramZone.slower;
      _confirmedZone = SmartProgramZone.slower;
      _playZone(
        SmartProgramZone.slower,
        chases: chases,
        scenes: scenes,
        banks: banks,
        patchedFixtures: patchedFixtures,
        universes: universes,
        service: service,
      );
      _statusController.add(const SmartProgramStatus(zone: SmartProgramZone.slower));
      return;
    }

    _beatTimes.add(now);
    // A longer window than the old 8: the estimator throws out gaps that
    // don't fit, so it needs enough of them left to be sure of the ones
    // that do. Twelve beats is about six seconds of music at club tempo.
    if (_beatTimes.length > 12) _beatTimes.removeAt(0);

    final estimate = estimateTempo(_beatTimes);
    // No agreement means the detector is picking up noise rather than a
    // pulse. Holding the current zone beats acting on a number we don't
    // believe — this is what used to strand the program in "slower" for a
    // whole set after a few missed beats dragged the average down.
    if (estimate == null || !estimate.isConfident) return;
    final liveBpm = estimate.bpm;

    final zone = _classify(program, liveBpm);
    _statusController.add(SmartProgramStatus(zone: _confirmedZone, liveBpm: liveBpm));

    if (zone == _confirmedZone) {
      _pendingZone = zone;
      _confirmTimer?.cancel();
      return;
    }
    if (zone != _pendingZone) {
      _pendingZone = zone;
      _confirmTimer?.cancel();
      final hold = switch (zone) {
        SmartProgramZone.faster => program.fasterHold,
        SmartProgramZone.slower => program.slowerHold,
        SmartProgramZone.base => _confirmedZone == SmartProgramZone.faster ? program.slowerHold : program.fasterHold,
      };
      _confirmTimer = Timer(hold, () {
        if (_pendingZone != zone || zone == _confirmedZone || _program == null) return;
        _confirmedZone = zone;
        _playZone(
          zone,
          chases: chases,
          scenes: scenes,
          banks: banks,
          patchedFixtures: patchedFixtures,
          universes: universes,
          service: service,
        );
        _statusController.add(SmartProgramStatus(zone: zone, liveBpm: liveBpm));
      });
    }
  }

  /// Auto-fade smears the lit→dark transition into a slow cross-fade, which
  /// is exactly wrong for a Beat Flash bank — so while one of those is
  /// playing on any layer, it's forced off, and put back the moment the
  /// program hands off to anything else.
  void _updateAutoFadeSuppression({required Iterable<ProgramTarget> targets, required List<Bank> banks}) {
    final isFlashBank = targets.any((target) {
      if (!target.isBank) return false;
      final matches = banks.where((b) => b.id == target.id);
      return matches.isNotEmpty && matches.first.isBeatFlash;
    });
    final instruction = _autoFadeGuard.onTargetChanged(
      isFlashBank: isFlashBank,
      autoFadeCurrentlyOn: isAutoFadeOn(),
    );
    if (instruction != null) setAutoFade(instruction);
  }

  SmartProgramZone _classify(SmartProgram program, double bpm) {
    if (bpm >= program.fasterTriggerBpm && program.hasFasterTarget) return SmartProgramZone.faster;
    if (bpm <= program.slowerTriggerBpm && program.hasSlowerTarget) return SmartProgramZone.slower;
    return SmartProgramZone.base;
  }

  void _playZone(
    SmartProgramZone zone, {
    required List<Chase> chases,
    required List<Scene> scenes,
    required List<Bank> banks,
    required List<PatchedFixture> patchedFixtures,
    required List<UniverseConfig> universes,
    required ArtNetService service,
  }) {
    final program = _program;
    if (program == null) return;
    final fade = _fadeOf(program, zone);
    // With beat sync armed the steps land on the detected beats, and the
    // zone's hold only matters as the fallback the player never reaches.
    final onBeat = beatSyncEnabled();
    final played = <ProgramTarget>[];

    for (final layer in program.drivenLayers) {
      if (_released.contains(layer.layerId)) continue;
      final player = playerFor(layer.layerId);
      final target = layer.effective(zone);
      final toPlay = target == null
          ? null
          : _chaseFor(target, program: program, zone: zone, fade: fade, onBeat: onBeat, chases: chases, banks: banks);
      if (toPlay == null) {
        // Nothing for this layer in this zone (it only has Faster, say, and
        // the song is at Base) — it sits dark until its zone comes round.
        player.stop();
        continue;
      }
      played.add(target!);
      player.play(
        chase: toPlay,
        scenes: scenes,
        banks: banks,
        patchedFixtures: patchedFixtures,
        universes: universes,
        service: service,
        beatStream: beatEvents,
        beatRate: beatRate(),
        flashLength: flashLength(),
        liveBeatRate: beatRate,
        liveFlashLength: flashLength,
        liveBeatSync: beatSyncEnabled,
        claim: false,
        onStep: (_) {},
      );
    }
    _updateAutoFadeSuppression(targets: played, banks: banks);
  }

  /// The chase a zone target becomes on one layer. The program's own
  /// per-zone fade always wins over whatever the chase/bank was configured
  /// with — that's the whole point of setting it here — and a chase plays
  /// all its steps on the layer the program put it on, whatever layers its
  /// own steps name.
  Chase? _chaseFor(
    ProgramTarget target, {
    required SmartProgram program,
    required SmartProgramZone zone,
    required Duration fade,
    required bool onBeat,
    required List<Chase> chases,
    required List<Bank> banks,
  }) {
    if (target.isBank) {
      final matches = banks.where((b) => b.id == target.id);
      if (matches.isEmpty) return null;
      // A bank has no timing of its own, so it becomes a one-step chase
      // stepping through its slots at this zone's pace.
      return Chase(
        id: 'smart-bank-${target.id}',
        name: matches.first.name,
        beatSync: onBeat,
        steps: [ChaseStep(bankId: target.id, hold: _zoneHold(program, zone), fade: fade)],
      );
    }
    final matches = chases.where((c) => c.id == target.id);
    if (matches.isEmpty) return null;
    final source = matches.first;
    return source.copyWith(
      beatSync: onBeat,
      steps: [for (final step in source.steps) step.copyWith(fade: fade, clearLayer: true)],
    );
  }

  /// Step time for a bank target, derived from the zone's own tempo: the
  /// faster zone should visibly step faster than the base one even though a
  /// bank carries no timing of its own.
  Duration _zoneHold(SmartProgram program, SmartProgramZone zone) {
    final bpm = switch (zone) {
      SmartProgramZone.base => program.baseBpm,
      SmartProgramZone.faster => program.fasterTriggerBpm,
      SmartProgramZone.slower => program.slowerTriggerBpm,
    };
    final beatMs = 60000 / bpm.clamp(20, 300);
    return Duration(milliseconds: beatMs.round());
  }

  void stop() {
    final layerIds = drivenLayerIds;
    _program = null;
    _released.clear();
    _beatSub?.cancel();
    _beatSub = null;
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _isSilent = false;
    final instruction = _autoFadeGuard.onStopped();
    if (instruction != null) setAutoFade(instruction);
    for (final id in layerIds) {
      playerFor(id).stop();
    }
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}

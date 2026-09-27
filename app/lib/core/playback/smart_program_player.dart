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

enum SmartProgramZone { base, faster, slower }

class SmartProgramStatus {
  final SmartProgramZone zone;
  final double? liveBpm;

  /// True while no beat has been heard for a while — the chase is blacked
  /// out and paused rather than stepping blind without any real tempo to
  /// follow. Resumes automatically (from the base zone) once beats return.
  final bool isSilent;

  const SmartProgramStatus({required this.zone, this.liveBpm, this.isSilent = false});
}

/// Drives a [SmartProgram]: watches the microphone's live beat tempo and
/// hands the shared [ChasePlayer] off between the program's base/faster/
/// slower chases as the song speeds up or slows down — each direction only
/// switches once the new tempo has held for that direction's configured
/// duration, so a single early/late beat doesn't cause flicker.
class SmartProgramPlayer {
  final ChasePlayer chasePlayer;
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
  ///
  /// A program already has the beat source open, so with beat sync armed its
  /// bank or chase steps on the beats themselves instead of on a timer
  /// derived from the zone's BPM. Without this a bank running inside a
  /// program simply ignored beat sync: the zone handed the player a chase
  /// with `beatSync` false and no beat stream, so it ticked along on
  /// [_zoneHold] no matter what the music did.
  final bool Function() beatSyncEnabled;
  final BeatRate Function() beatRate;
  final Duration Function() flashLength;

  /// The app-wide auto-fade switch, read and (temporarily) written — see
  /// [_suppressAutoFadeFor]. Defaults to a no-op pair so tests and callers
  /// that don't care about this can ignore it entirely.
  final bool Function() isAutoFadeOn;
  final void Function(bool) setAutoFade;

  SmartProgramPlayer({
    required this.chasePlayer,
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

  /// How long to wait without a single beat before assuming the music has
  /// stopped (rather than just being between two real beats of a slow song
  /// — even 40 BPM is a beat every 1.5s, so this leaves a wide margin).
  static const _silenceTimeout = Duration(seconds: 4);

  final _statusController = StreamController<SmartProgramStatus>.broadcast();
  Stream<SmartProgramStatus> get statusStream => _statusController.stream;

  bool get isRunning => _program != null;
  String? get activeProgramId => _program?.id;
  SmartProgramZone get currentZone => _confirmedZone;

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
    _beatTimes.clear();
    _pendingZone = SmartProgramZone.base;
    _confirmedZone = SmartProgramZone.base;
    _isSilent = false;
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
  /// Playback is only re-triggered when the current zone's *target* or
  /// *fade* actually changed — thresholds and hold times take effect on the
  /// next beat by themselves, and restarting the chase for those would jump
  /// the look for no reason.
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
    final targetChanged = _targetOf(current, zone) != _targetOf(program, zone);
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

  static ProgramTarget? _targetOf(SmartProgram program, SmartProgramZone zone) => switch (zone) {
    SmartProgramZone.base => program.baseTarget,
    SmartProgramZone.faster => program.fasterTarget ?? program.baseTarget,
    SmartProgramZone.slower => program.slowerTarget ?? program.baseTarget,
  };

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
  /// beat later restarts cleanly from the base zone.
  void _enterSilence({required ArtNetService service, required List<UniverseConfig> universes}) {
    final program = _program;
    if (program == null || _isSilent) return;
    _isSilent = true;
    _confirmTimer?.cancel();
    // Let the rig die out gently over the program's blackout fade instead of
    // cutting to black — `fadeToBlack` stops playback itself and yields to
    // anything fired mid-fade.
    chasePlayer.fadeToBlack(over: program.blackoutFade, service: service, universes: universes);
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
  /// is exactly wrong for a Beat Flash bank — so while one of those is the
  /// zone actually playing, it's forced off, and put back the moment the
  /// program hands off to anything else.
  void _updateAutoFadeSuppression({required ProgramTarget target, required List<Bank> banks}) {
    final matches = target.isBank ? banks.where((b) => b.id == target.id) : const <Bank>[];
    final isFlashBank = matches.isNotEmpty && matches.first.isBeatFlash;
    final instruction = _autoFadeGuard.onTargetChanged(
      isFlashBank: isFlashBank,
      autoFadeCurrentlyOn: isAutoFadeOn(),
    );
    if (instruction != null) setAutoFade(instruction);
  }

  SmartProgramZone _classify(SmartProgram program, double bpm) {
    if (bpm >= program.fasterTriggerBpm && program.fasterTarget != null) return SmartProgramZone.faster;
    if (bpm <= program.slowerTriggerBpm && program.slowerTarget != null) return SmartProgramZone.slower;
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
    final target = switch (zone) {
      SmartProgramZone.base => program.baseTarget,
      SmartProgramZone.faster => program.fasterTarget ?? program.baseTarget,
      SmartProgramZone.slower => program.slowerTarget ?? program.baseTarget,
    };
    if (target == null) return;
    final fade = switch (zone) {
      SmartProgramZone.base => program.baseFade,
      SmartProgramZone.faster => program.fasterFade,
      SmartProgramZone.slower => program.slowerFade,
    };

    _updateAutoFadeSuppression(target: target, banks: banks);

    // With beat sync armed the steps land on the detected beats, and the
    // zone's hold only matters as the fallback the player never reaches.
    final onBeat = beatSyncEnabled();

    // The program's own per-zone fade always wins over whatever the
    // chase/bank was configured with — that's the whole point of setting it
    // here.
    final Chase toPlay;
    if (target.isBank) {
      final matches = banks.where((b) => b.id == target.id);
      if (matches.isEmpty) return;
      // A bank has no timing of its own, so it becomes a one-step chase
      // stepping through its slots at this zone's pace.
      toPlay = Chase(
        id: 'smart-bank-${target.id}',
        name: matches.first.name,
        beatSync: onBeat,
        steps: [ChaseStep(bankId: target.id, hold: _zoneHold(program, zone), fade: fade)],
      );
    } else {
      final matches = chases.where((c) => c.id == target.id);
      if (matches.isEmpty) return;
      final source = matches.first;
      toPlay = source.copyWith(
        beatSync: onBeat,
        steps: [
          for (final step in source.steps)
            ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: step.hold, fade: fade),
        ],
      );
    }

    chasePlayer.play(
      chase: toPlay,
      scenes: scenes,
      banks: banks,
      patchedFixtures: patchedFixtures,
      universes: universes,
      service: service,
      beatStream: onBeat ? beatEvents : null,
      beatRate: beatRate(),
      flashLength: flashLength(),
      liveBeatRate: beatRate,
      liveFlashLength: flashLength,
      onStep: (_) {},
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
    _program = null;
    _beatSub?.cancel();
    _beatSub = null;
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _isSilent = false;
    final instruction = _autoFadeGuard.onStopped();
    if (instruction != null) setAutoFade(instruction);
    chasePlayer.stop();
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}

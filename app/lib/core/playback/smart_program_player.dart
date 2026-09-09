import 'dart:async';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/smart_program.dart';
import '../../models/universe_config.dart';
import '../artnet/artnet_service.dart';
import '../audio/beat_detector.dart';
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
  final BeatDetectorService beatService;

  SmartProgramPlayer({required this.chasePlayer, required this.beatService});

  StreamSubscription<DateTime>? _beatSub;
  Timer? _confirmTimer;
  Timer? _silenceTimer;
  final List<DateTime> _beatTimes = [];
  SmartProgramZone _pendingZone = SmartProgramZone.base;
  SmartProgramZone _confirmedZone = SmartProgramZone.base;
  SmartProgram? _program;
  bool _isSilent = false;

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

    _beatSub = beatService.beatEvents.listen((now) {
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

  void _resetSilenceTimer({required ArtNetService service, required List<UniverseConfig> universes}) {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () => _enterSilence(service: service, universes: universes));
  }

  /// No beat has arrived for [_silenceTimeout] — the music has presumably
  /// stopped (or was never there). Blacks out and stops stepping instead of
  /// looping the base chase forever with nothing real driving it; a fresh
  /// beat later restarts cleanly from the base zone.
  void _enterSilence({required ArtNetService service, required List<UniverseConfig> universes}) {
    if (_program == null || _isSilent) return;
    _isSilent = true;
    _confirmTimer?.cancel();
    chasePlayer.stop();
    service.blackoutAll(universes);
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
      // Music is back after a silent stretch — start clean from the base
      // zone rather than resuming mid-classification on stale beat history.
      _isSilent = false;
      _beatTimes.clear();
      _pendingZone = SmartProgramZone.base;
      _confirmedZone = SmartProgramZone.base;
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
      return;
    }

    _beatTimes.add(now);
    if (_beatTimes.length > 8) _beatTimes.removeAt(0);
    if (_beatTimes.length < 3) return;

    final intervals = <int>[];
    for (var i = 1; i < _beatTimes.length; i++) {
      intervals.add(_beatTimes[i].difference(_beatTimes[i - 1]).inMilliseconds);
    }
    final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
    if (avgMs <= 0) return;
    final liveBpm = 60000 / avgMs;

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

  SmartProgramZone _classify(SmartProgram program, double bpm) {
    if (bpm >= program.fasterTriggerBpm && program.fasterChaseId != null) return SmartProgramZone.faster;
    if (bpm <= program.slowerTriggerBpm && program.slowerChaseId != null) return SmartProgramZone.slower;
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
    final chaseId = switch (zone) {
      SmartProgramZone.base => program.baseChaseId,
      SmartProgramZone.faster => program.fasterChaseId ?? program.baseChaseId,
      SmartProgramZone.slower => program.slowerChaseId ?? program.baseChaseId,
    };
    if (chaseId == null) return;
    final matches = chases.where((c) => c.id == chaseId);
    if (matches.isEmpty) return;
    final source = matches.first;
    final fade = switch (zone) {
      SmartProgramZone.base => program.baseFade,
      SmartProgramZone.faster => program.fasterFade,
      SmartProgramZone.slower => program.slowerFade,
    };
    // The program's own per-zone fade always wins over whatever the
    // chase/bank was configured with — that's the whole point of setting it
    // here.
    final withFade = source.copyWith(
      steps: [
        for (final step in source.steps)
          ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: step.hold, fade: fade),
      ],
    );
    chasePlayer.play(
      chase: withFade,
      scenes: scenes,
      banks: banks,
      patchedFixtures: patchedFixtures,
      universes: universes,
      service: service,
      onStep: (_) {},
    );
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
    chasePlayer.stop();
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}

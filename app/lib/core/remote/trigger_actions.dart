
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/provider_reader.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/tempo_providers.dart';

export '../../state/provider_reader.dart' show ReadProvider;

/// Fires [chase] on the shared player exactly the way the Dashboard does:
/// superseding any Smart Program, and wiring up beat sync when armed.
///
/// [dashboardTiming] says whether this chase is one the Dashboard's own
/// Hold/Fade governs — always true for a bank, and for a saved chase only
/// while "Override saved timing" is on. Auto-fade rides on the same rule:
/// a chase keeping its own timing keeps its own fades too.
Future<void> startChase(ReadProvider read, Chase chase, {bool dashboardTiming = true}) async {
  read(smartProgramPlayerProvider).stop();
  final service = read(artNetServiceProvider);
  Stream<DateTime>? beatStream;
  if (chase.beatSync) {
    final beatService = read(activeBeatSourceProvider);
    if (await beatService.start()) beatStream = read(beatPredictorProvider).events;
  }
  read(playbackControllerProvider).play(
    chase: chase,
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: service,
    beatStream: beatStream,
    beatRate: read(beatRateProvider),
    flashLength: read(flashLengthProvider),
    liveBeatRate: () => read(beatRateProvider),
    liveFlashLength: () => read(flashLengthProvider),
    onStep: (_) {},
    // Read fresh on every step rather than captured here, so tempo changes
    // reach the rig without restarting the chase. Returns null while
    // auto-fade is off, leaving the step's own fade alone.
    fadeOverride: dashboardTiming
        ? () {
            final tempo = read(tempoProvider);
            return tempo.autoFade ? tempo.fade : null;
          }
        : null,
  );
}

/// A bank has no timing of its own, so it always runs at the Dashboard's
/// Hold/Fade — override switch or not.
Chase bankChase(ReadProvider read, {required String bankId, required String name}) {
  final tempo = read(tempoProvider);
  return Chase(
    id: 'dashboard-bank-$bankId',
    name: name,
    steps: [ChaseStep(bankId: bankId, hold: tempo.hold, fade: tempo.fade)],
    beatSync: read(beatSyncEnabledProvider),
  );
}

/// A saved chase as the Dashboard plays it: beat sync always follows the
/// app-wide switch, per-step timing is replaced only while "Override saved
/// timing" is on.
Chase chaseAsDashboardPlaysIt(ReadProvider read, Chase saved) {
  final tempo = read(tempoProvider);
  final beatSync = read(beatSyncEnabledProvider);
  if (!tempo.overrideTiming) return saved.copyWith(beatSync: beatSync);
  return saved.copyWith(
    beatSync: beatSync,
    steps: [
      for (final step in saved.steps)
        ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: tempo.hold, fade: tempo.fade),
    ],
  );
}

/// Starts a bank/chase, or stops it if it's the one already running —
/// the same toggle a Dashboard tile performs.
Future<String> togglePlayable(
  ReadProvider read, {
  required String id,
  required bool isBank,
  required String name,
}) async {
  final player = read(playbackControllerProvider);
  final current = read(nowPlayingProvider);
  final isThisActive = player.isPlaying && current?.id == id && current?.kind != PlaybackKind.smartProgram;
  if (isThisActive) {
    player.stop();
    read(nowPlayingProvider.notifier).state = null;
    return 'Stopped $name';
  }
  if (!read(artNetServiceProvider).isConnected) return 'Not connected — check Settings';

  final Chase chase;
  if (isBank) {
    chase = bankChase(read, bankId: id, name: name);
  } else {
    final matches = read(chasesProvider).where((c) => c.id == id);
    if (matches.isEmpty) return 'Chase no longer exists';
    chase = chaseAsDashboardPlaysIt(read, matches.first);
  }
  await startChase(read, chase, dashboardTiming: isBank || read(tempoProvider).overrideTiming);
  // A step whose scene or bank no longer exists (deleted out from under it)
  // flattens to nothing, and `play` quietly declines to run zero steps —
  // reporting "Started" anyway would leave nowPlaying pointing at a bank
  // or chase that isn't actually doing anything.
  if (!player.isPlaying) return '$name has no valid steps to play';
  read(nowPlayingProvider.notifier).state = NowPlaying(
    id: id,
    kind: isBank ? PlaybackKind.bank : PlaybackKind.chase,
    name: name,
  );
  return 'Started $name';
}

/// Starts a Smart Program, or stops it if it's the one already running.
Future<String> toggleSmartProgramById(ReadProvider read, String programId) async {
  final smartPlayer = read(smartProgramPlayerProvider);
  final matches = read(smartProgramsProvider).where((p) => p.id == programId);
  if (matches.isEmpty) return 'Smart program no longer exists';
  final program = matches.first;

  if (smartPlayer.isRunning && smartPlayer.activeProgramId == programId) {
    smartPlayer.stop();
    read(nowPlayingProvider.notifier).state = null;
    return 'Stopped ${program.name}';
  }
  final service = read(artNetServiceProvider);
  if (!service.isConnected) return 'Not connected — check Settings';
  if (!program.hasBaseTarget) return '${program.name} has no base chase or bank set';

  read(playbackControllerProvider).stop();
  read(nowPlayingProvider.notifier).state = null;
  final started = await smartPlayer.start(
    program: program,
    chases: read(chasesProvider),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: service,
  );
  if (!started) return 'Could not open the microphone for tempo tracking';
  read(nowPlayingProvider.notifier).state = NowPlaying(
    id: program.id,
    kind: PlaybackKind.smartProgram,
    name: program.name,
  );
  return 'Started ${program.name}';
}

/// Re-fires whatever bank or chase is playing so it picks up a changed
/// timing setting straight away.
///
/// Shared rather than owned by the Dashboard, because the controls that
/// need it moved into the control panel and both have to behave the same.
///
/// [timingOnly] marks the Hold/Fade sliders as the caller: those don't
/// touch a saved chase at all while "Override saved timing" is off, so
/// restarting for them would kick the chase back to step 1 for nothing.
///
/// A running Smart Program isn't restarted for a timing change — it drives
/// its own — but it *is* re-fired for anything else, beat sync being the
/// one that matters: whether the steps follow the beats is decided when a
/// zone is fired, so without this the switch did nothing to the bank a
/// program was already running.
Future<void> restartActiveTrigger(ReadProvider read, {bool timingOnly = false}) async {
  final player = read(playbackControllerProvider);
  final current = read(nowPlayingProvider);
  if (!player.isPlaying || current == null) return;
  if (current.kind == PlaybackKind.smartProgram) {
    if (timingOnly) return;
    read(smartProgramPlayerProvider).replayCurrentZone(
      chases: read(chasesProvider),
      scenes: read(scenesProvider),
      banks: read(banksProvider),
      patchedFixtures: read(patchedFixturesProvider),
      universes: read(universesProvider),
      service: read(artNetServiceProvider),
    );
    return;
  }

  final Chase chase;
  if (current.kind == PlaybackKind.bank) {
    final banks = read(banksProvider).where((b) => b.id == current.id);
    if (banks.isEmpty) return;
    chase = bankChase(read, bankId: current.id, name: banks.first.name);
  } else {
    if (timingOnly && !read(tempoProvider).overrideTiming) return;
    final saved = read(chasesProvider).where((c) => c.id == current.id);
    if (saved.isEmpty) return;
    chase = chaseAsDashboardPlaysIt(read, saved.first);
  }
  await startChase(
    read,
    chase,
    dashboardTiming: current.kind == PlaybackKind.bank || read(tempoProvider).overrideTiming,
  );
}

/// Starts whatever played last again — what the control dock's Start
/// button does, so you can stop for a moment and pick the show back up
/// without hunting for the tile you fired it from.
Future<String> resumeLastPlayed(ReadProvider read) async {
  final last = read(lastPlayedProvider);
  if (last == null) return 'Nothing has played yet';
  if (last.kind == PlaybackKind.smartProgram) return toggleSmartProgramById(read, last.id);
  return togglePlayable(read, id: last.id, isBank: last.isBank, name: last.name);
}

/// Pushes the saved version of a Smart Program onto the runner if that same
/// program is currently playing.
///
/// Call this after any edit. Without it, saving a program changed nothing
/// until it was stopped and started again — the runner holds the program it
/// was handed at start, so the editor and the rig disagreed.
void syncRunningSmartProgram(ReadProvider read) {
  final player = read(smartProgramPlayerProvider);
  final id = player.activeProgramId;
  if (id == null) return;
  final matches = read(smartProgramsProvider).where((p) => p.id == id);
  if (matches.isEmpty) return;
  player.updateProgram(
    matches.first,
    chases: read(chasesProvider),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: read(artNetServiceProvider),
  );
}

/// Arms or disarms mic beat sync — the same app-wide switch the Dashboard,
/// the Banks tab and the control dock share. [on] null toggles it.
///
/// Turning it on opens the microphone, so the very first time has to happen
/// with the app in front of you: Android only grants the mic permission from
/// a visible prompt. After that this works from anywhere.
Future<String> setBeatSync(ReadProvider read, {bool? on}) async {
  final current = read(beatSyncEnabledProvider);
  final target = on ?? !current;
  if (target == current) return 'Beat sync already ${target ? 'on' : 'off'}';
  final error = await read(beatSyncEnabledProvider.notifier).setEnabled(target);
  if (error != null) return error;
  // Whatever is playing has to be re-fired to pick the switch up — see
  // [restartActiveTrigger].
  await restartActiveTrigger(read);
  return 'Beat sync ${target ? 'on' : 'off'}';
}

/// Toggles the beat predictor that fills in beats the mic misses — the same
/// switch as the control dock's "Predict" button. [on] null toggles it.
String setBeatPrediction(ReadProvider read, {bool? on}) {
  final current = read(beatPredictionEnabledProvider);
  final target = on ?? !current;
  if (target == current) return 'Predict already ${target ? 'on' : 'off'}';
  read(beatPredictionEnabledProvider.notifier).setEnabled(target);
  return 'Predict ${target ? 'on' : 'off'}';
}

/// Toggles auto-fade — the tempo-linked fade time the control dock's
/// "AutoFade" button and the Control Panel's switch share. [on] null toggles
/// it.
String setAutoFade(ReadProvider read, {bool? on}) {
  final tempo = read(tempoProvider);
  final target = on ?? !tempo.autoFade;
  if (target == tempo.autoFade) return 'AutoFade already ${target ? 'on' : 'off'}';
  read(tempoProvider.notifier).setAutoFade(target);
  return 'AutoFade ${target ? 'on' : 'off'}';
}

/// Something the remote endpoint can fire, and the name it answers to.
class RemoteTarget {
  final String id;
  final String name;
  final String kind; // 'bank' | 'chase' | 'smart'

  /// Pinned to the Dashboard as a Quick Trigger (or a Smart Program). The
  /// watch menu shows only these, so what's on your wrist mirrors what you
  /// curated on the Dashboard instead of every bank in the project.
  final bool onDashboard;

  const RemoteTarget({
    required this.id,
    required this.name,
    required this.kind,
    this.onDashboard = false,
  });
}

/// Everything reachable by name: the Dashboard's Quick Triggers and Smart
/// Programs first (those are what the tiles show), then any other bank or
/// chase, so a name typed into a macro finds the obvious thing.
List<RemoteTarget> remoteTargets(ReadProvider read) {
  final banks = read(banksProvider);
  final chases = read(chasesProvider);
  final quick = read(dashboardTriggersProvider);
  final targets = <RemoteTarget>[];
  final seen = <String>{};

  void add(String id, String name, String kind, {bool onDashboard = false}) {
    if (!seen.add('$kind:$id')) return;
    targets.add(RemoteTarget(id: id, name: name, kind: kind, onDashboard: onDashboard));
  }

  for (final trigger in quick) {
    if (trigger.kind == TriggerKind.bank) {
      final match = banks.where((b) => b.id == trigger.id);
      if (match.isNotEmpty) add(match.first.id, match.first.name, 'bank', onDashboard: true);
    } else {
      final match = chases.where((c) => c.id == trigger.id);
      if (match.isNotEmpty) add(match.first.id, match.first.name, 'chase', onDashboard: true);
    }
  }
  for (final program in read(smartProgramsProvider)) {
    add(program.id, program.name, 'smart', onDashboard: true);
  }
  for (final bank in banks) {
    add(bank.id, bank.name, 'bank');
  }
  for (final chase in chases) {
    add(chase.id, chase.name, 'chase');
  }
  return targets;
}

/// Toggles whatever answers to [name] (case-insensitive). Returns a message
/// describing what happened, for the caller to report back.
Future<String> fireByName(ReadProvider read, String name) async {
  final wanted = name.trim().toLowerCase();
  if (wanted.isEmpty) return 'No name given';
  final matches = remoteTargets(read).where((t) => t.name.toLowerCase() == wanted);
  if (matches.isEmpty) return 'Nothing called "$name"';
  final target = matches.first;
  if (target.kind == 'smart') return toggleSmartProgramById(read, target.id);
  return togglePlayable(read, id: target.id, isBank: target.kind == 'bank', name: target.name);
}

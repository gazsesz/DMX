
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
Future<void> startChase(ReadProvider read, Chase chase) async {
  read(smartProgramPlayerProvider).stop();
  final service = read(artNetServiceProvider);
  Stream<DateTime>? beatStream;
  if (chase.beatSync) {
    final beatService = read(beatDetectorProvider);
    if (await beatService.start()) beatStream = beatService.beatEvents;
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
    onStep: (_) {},
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
  await startChase(read, chase);
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

/// Something the remote endpoint can fire, and the name it answers to.
class RemoteTarget {
  final String id;
  final String name;
  final String kind; // 'bank' | 'chase' | 'smart'

  const RemoteTarget({required this.id, required this.name, required this.kind});
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

  void add(String id, String name, String kind) {
    if (!seen.add('$kind:$id')) return;
    targets.add(RemoteTarget(id: id, name: name, kind: kind));
  }

  for (final trigger in quick) {
    if (trigger.kind == TriggerKind.bank) {
      final match = banks.where((b) => b.id == trigger.id);
      if (match.isNotEmpty) add(match.first.id, match.first.name, 'bank');
    } else {
      final match = chases.where((c) => c.id == trigger.id);
      if (match.isNotEmpty) add(match.first.id, match.first.name, 'chase');
    }
  }
  for (final program in read(smartProgramsProvider)) {
    add(program.id, program.name, 'smart');
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

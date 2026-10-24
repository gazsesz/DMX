
import '../../models/chase.dart';import '../../models/dashboard_trigger.dart';
import '../../models/layer.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/dimmer_dropout_providers.dart';
import '../../state/color_override_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/movement_live_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/provider_reader.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/tempo_providers.dart';

export '../../state/provider_reader.dart' show ReadProvider;

/// Fires [chase] exactly the way the Dashboard does: one lane per layer its
/// steps name, each taking its layer back from the Smart Program, with beat
/// sync wired up when armed. Every started lane is marked as [playing].
/// Returns the layers that started.
///
/// [dashboardTiming] says whether this chase is one the Dashboard's own
/// Hold/Fade governs — always true for a bank, and for a saved chase only
/// while "Override saved timing" is on. Auto-fade rides on the same rule:
/// a chase keeping its own timing keeps its own fades too.
Future<List<String>> startChase(
  ReadProvider read,
  Chase chase, {
  required NowPlaying playing,
  bool dashboardTiming = true,
  bool exclusive = false,
}) {
  // Read on every step — see [stableRead].
  read = stableRead(read);
  return startLayeredChase(
    read,
    chase,
    playing: playing,
    followBeatSync: true,
    exclusive: exclusive,
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

/// A saved chase as the Dashboard plays it: beat sync always follows the
/// app-wide switch, per-step timing is replaced only while "Override saved
/// timing" is on.
Chase chaseAsDashboardPlaysIt(ReadProvider read, Chase saved) {
  final tempo = read(tempoProvider);
  final beatSync = read(beatSyncEnabledProvider);
  if (!tempo.overrideTiming) return saved.copyWith(beatSync: beatSync);
  return saved.copyWith(
    beatSync: beatSync,
    // A free-running lane keeps its own steps' timing — that is the point of it.
    steps: [
      for (final step in saved.steps)
        saved.timingOfLane(step.layerId ?? layer1Id) == LaneTiming.free
            ? step
            : step.copyWith(hold: tempo.hold, fade: tempo.fade),
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
  if (layersPlaying(read, id).isNotEmpty) {
    stopEverywhere(read, id);
    return 'Stopped $name';
  }
  if (!read(artNetServiceProvider).isConnected) return 'Not connected — check Settings';

  if (isBank) {
    // A bank fired on its own plays on Layer 1, the way it always has.
    final banks = read(banksProvider).where((b) => b.id == id);
    if (banks.isEmpty) return 'Bank no longer exists';
    return runBankOnLayer(read, bank: banks.first, layerId: layer1Id) ?? 'Started $name';
  }
  final matches = read(chasesProvider).where((c) => c.id == id);
  if (matches.isEmpty) return 'Chase no longer exists';
  final started = await startChase(
    read,
    chaseAsDashboardPlaysIt(read, matches.first),
    playing: NowPlaying(id: id, kind: PlaybackKind.chase, name: name),
    dashboardTiming: read(tempoProvider).overrideTiming,
    exclusive: true,
  );
  // A step whose scene or bank no longer exists (deleted out from under it)
  // flattens to nothing, and `play` quietly declines to run zero steps —
  // reporting "Started" anyway would leave nowPlaying pointing at a bank
  // or chase that isn't actually doing anything.
  if (started.isEmpty) return '$name has no valid steps to play';
  return 'Started $name';
}

/// Starts a Smart Program, or stops it if it's the one already running.
Future<String> toggleSmartProgramById(ReadProvider read, String programId) async {
  final smartPlayer = read(smartProgramPlayerProvider);
  final matches = read(smartProgramsProvider).where((p) => p.id == programId);
  if (matches.isEmpty) return 'Smart program no longer exists';
  final program = matches.first;

  if (smartPlayer.isRunning && smartPlayer.activeProgramId == programId) {
    stopSmartProgram(read);
    return 'Stopped ${program.name}';
  }
  return startSmartProgram(read, program);
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
  final smart = read(smartProgramPlayerProvider);
  if (smart.isRunning && !timingOnly) {
    smart.replayCurrentZone(
      chases: read(chasesProvider),
      scenes: read(scenesProvider),
      banks: read(banksProvider),
      patchedFixtures: read(patchedFixturesProvider),
      universes: read(universesProvider),
      service: read(artNetServiceProvider),
    );
  }

  // Everything else plain-playing, layer by layer. A chase is restarted
  // once, which brings all its lanes back together.
  final restartedChases = <String>{};
  for (final layer in read(layersProvider)) {
    final current = read(nowPlayingForLayerProvider(layer.id));
    if (current == null || current.kind == PlaybackKind.smartProgram) continue;
    if (!read(chasePlayerProvider(layer.id)).isPlaying) continue;
    if (current.kind == PlaybackKind.bank) {
      final banks = read(banksProvider).where((b) => b.id == current.id);
      if (banks.isEmpty) continue;
      // Nothing of the dock's to pick up for a bank on its own timing.
      if (timingOnly && banks.first.ownTiming) continue;
      runBankOnLayer(read, bank: banks.first, layerId: layer.id);
      continue;
    }
    if (timingOnly && !read(tempoProvider).overrideTiming) continue;
    if (!restartedChases.add(current.id)) continue;
    final saved = read(chasesProvider).where((c) => c.id == current.id);
    if (saved.isEmpty) continue;
    await startChase(
      read,
      chaseAsDashboardPlaysIt(read, saved.first),
      playing: current,
      dashboardTiming: read(tempoProvider).overrideTiming,
    );
  }
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
  final id = read(smartProgramPlayerProvider).activeProgramId;
  if (id == null) return;
  final matches = read(smartProgramsProvider).where((p) => p.id == id);
  if (matches.isEmpty) return;
  updateRunningSmartProgram(read, matches.first);
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

/// Switches the dimmer dropout on or off — the same switch as the one on the
/// Layers screen and the control panel. [on] null toggles it. It acts on the
/// hand-set dropout; a running Smart Program's zone or a chase keeps its own.
String setDropout(ReadProvider read, {bool? on}) {
  final controller = read(dimmerDropoutProvider.notifier);
  final current = read(dimmerDropoutProvider);
  final target = on ?? !current.enabled;
  if (target == current.enabled) return 'Dropout already ${target ? 'on' : 'off'}';
  controller.update(current.copyWith(enabled: target));
  return 'Dropout ${target ? 'on' : 'off'}';
}

/// Sets the Movement strip's knobs (Size ×0–2, Speed ×0.25–4, Shift 0–1,
/// Smooth 0–1) — the same ones as on the strip. Values out of range are
/// pulled into range; [reset] puts every knob back to neutral first.
String setMovementLive(
  ReadProvider read, {
  double? size,
  double? speed,
  double? shift,
  double? smooth,
  bool reset = false,
}) {
  final notifier = read(movementLiveProvider.notifier);
  if (reset) notifier.reset();
  if (size != null || speed != null || shift != null || smooth != null) {
    notifier.set(size: size, speed: speed, shift: shift, smooth: smooth);
  }
  final now = read(movementLiveProvider);
  return now.isNeutral
      ? 'Movement knobs neutral'
      : 'Movement size ${now.size.toStringAsFixed(2)} · speed ${now.speed.toStringAsFixed(2)} · '
            'shift ${now.shift.toStringAsFixed(2)} · smooth ${now.smooth.toStringAsFixed(2)}';
}

/// Lays a basic colour (by [name], or a custom [hex]) over the scenes, the way
/// the Colour strip does; [off] gives the scenes their own colours back.
/// [group] limits it to a saved fixture group by name, otherwise it goes to
/// the whole rig. With nothing given it just reports the current state.
String setLiveColor(ReadProvider read, {String? name, String? hex, String? group, bool off = false}) {
  final notifier = read(liveColorProvider.notifier);
  if (off) {
    notifier.auto();
    return 'Colour: scene';
  }
  if (name == null && hex == null) {
    if (group != null) {
      final groupId = _groupIdNamed(read, group);
      if (groupId == null) throw StateError('No group called "$group"');
      notifier.setGroup(groupId);
    }
    return _liveColorText(read);
  }
  final color = hex != null ? liveColorFromHex(hex) : liveColorNamed(name!);
  if (color == null) {
    throw StateError('Unknown colour "${hex ?? name}" — try ${[for (final c in liveColors) c.id].join(', ')} or hex=RRGGBB');
  }
  String? groupId;
  if (group != null) {
    groupId = _groupIdNamed(read, group);
    if (groupId == null) throw StateError('No group called "$group"');
  }
  notifier.set(color, groupId: groupId);
  return _liveColorText(read);
}

String? _groupIdNamed(ReadProvider read, String name) {
  final wanted = name.trim().toLowerCase();
  for (final g in read(fixtureGroupsProvider)) {
    if (g.name.trim().toLowerCase() == wanted) return g.id;
  }
  return null;
}

String _liveColorText(ReadProvider read) {
  final live = read(liveColorProvider);
  final color = live.color;
  if (color == null) return 'Colour: scene';
  final groups = [for (final g in read(fixtureGroupsProvider)) if (g.id == live.groupId) g.name];
  return 'Colour: ${color.label}${groups.isEmpty ? '' : ' on ${groups.first}'}';
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

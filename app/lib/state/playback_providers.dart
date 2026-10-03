import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/chase_player.dart';
import '../core/playback/smart_program_player.dart';
import '../models/bank.dart';
import '../models/chase.dart';
import '../models/layer.dart';
import '../models/smart_program.dart';
import 'artnet_providers.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'fixture_providers.dart';
import 'layer_providers.dart';
import 'momentary_fx_providers.dart';
import 'provider_reader.dart';
import 'audio_providers.dart';
import 'scene_providers.dart';
import 'smart_program_providers.dart';
import 'tempo_providers.dart';

/// One independent [ChasePlayer] per layer id — Layer 1's entry is what
/// [playbackControllerProvider] aliases to below, so every pre-existing
/// consumer of that name keeps working unchanged. Starting a bank/chase on
/// one layer never supersedes whatever another layer is running; the layers
/// stay conflict-free as long as the scenes each one plays leave the
/// channels the others own out of [Scene.fixtureValues] — e.g. one layer
/// runs a color/beam chase on a moving head while another runs a slow
/// pan/tilt sweep on the same fixture, each only ever writing its own
/// attributes (see the Scene editor's "INCLUDES" toggles).
final chasePlayerProvider = Provider.family<ChasePlayer, String>((ref, layerId) {
  final player = ChasePlayer(layerId: layerId);
  ref.onDispose(player.dispose);
  return player;
});

/// What's running on a given layer id, mirroring the old per-layer
/// StateProviders this replaces.
final nowPlayingForLayerProvider = StateProvider.family<NowPlaying?, String>((ref, layerId) => null);

/// A single player shared by every screen that can start a bank/chase
/// (Dashboard triggers, the Banks "Run Bank" preview, the Chase editor's
/// "Preview"). Starting playback anywhere always cleanly supersedes
/// whatever was already running elsewhere, instead of two independent
/// loops racing over the same universes.
final playbackControllerProvider = chasePlayerProvider(layer1Id);

/// The single Smart Program runner. It plays on each layer's own
/// [ChasePlayer] above — so a program's zone switches use the same
/// machinery as a plain bank/chase on that layer. Anything that starts
/// something else on a layer the program is driving must take that layer
/// back first ([releaseLayersFromSmart]), or the program's beat listener
/// would reassert its own target there on the next zone change.
final smartProgramPlayerProvider = Provider<SmartProgramPlayer>((ref) {
  final player = SmartProgramPlayer(
    playerFor: (layerId) => ref.read(chasePlayerProvider(layerId)),
    beatService: ref.watch(activeBeatSourceProvider),
    // Read, not watched: the program is driven from callbacks, and a
    // rebuilt player would drop the running show on the floor.
    beatSyncEnabled: () => ref.read(beatSyncEnabledProvider),
    beatRate: () => ref.read(beatRateProvider),
    flashLength: () => ref.read(flashLengthProvider),
    // Routed through the shared predictor so a Smart Program's tempo
    // tracking rides out a missed beat the same way a beat-synced chase
    // does, instead of the classifier alone having to fold it back in.
    beatEvents: ref.watch(beatPredictorProvider).events,
    // Lets the player suspend the app-wide Auto-Fade switch for as long as
    // a Beat Flash bank is the active zone, and put it back once the
    // program moves off it — see `SmartProgramPlayer._updateAutoFadeSuppression`.
    isAutoFadeOn: () => ref.read(tempoProvider).autoFade,
    setAutoFade: (value) => ref.read(tempoProvider.notifier).setAutoFade(value),
  );
  ref.onDispose(player.dispose);
  return player;
});

/// The running Smart Program's zone and live tempo, for anything that isn't
/// the Dashboard — the control dock shows which part of a program is
/// playing, which is the thing you actually want to know from another tab.
final smartProgramStatusProvider = StreamProvider<SmartProgramStatus>((ref) {
  return ref.watch(smartProgramPlayerProvider).statusStream;
});

/// The last thing that played, remembered after it stops.
///
/// [nowPlayingProvider] goes null on stop, which is correct for "what is
/// running" but leaves the dock's Start button with nothing to resume. This
/// shadows it and simply never clears.
///
/// It has to be *alive* before the first trigger fires, or it misses it —
/// Riverpod builds a provider on first read, and by then the thing to
/// remember may already have stopped. [watchLastPlayed] does that once at
/// startup; don't rely on the dock being on screen to bring it into
/// existence.
final lastPlayedProvider = StateNotifierProvider<LastPlayedNotifier, NowPlaying?>((ref) {
  final notifier = LastPlayedNotifier();
  ref.listen<NowPlaying?>(
    nowPlayingProvider,
    (_, next) {
      if (next != null) notifier.remember(next);
    },
    fireImmediately: true,
  );
  return notifier;
});

class LastPlayedNotifier extends StateNotifier<NowPlaying?> {
  LastPlayedNotifier() : super(null);

  void remember(NowPlaying playing) => state = playing;
}

/// Brings [lastPlayedProvider] into existence so it starts listening.
/// Called once at startup — see that provider for why it can't wait.
void watchLastPlayed(ReadProvider read) => read(lastPlayedProvider);

/// Which bottom-nav/rail section is currently visible. AppShell keeps every
/// section's screen mounted (via IndexedStack) so switching tabs doesn't
/// reset their state — but that means a screen owning a "preview while
/// editing" style playback (e.g. Banks' Run Bank button) never sees a
/// normal `dispose()` when the user navigates away, so it needs this to
/// notice it's no longer the visible tab and stop itself.
final activeSectionIndexProvider = StateProvider<int>((ref) => 0);

enum PlaybackKind { bank, chase, smartProgram }

/// What's currently active on the shared player, if anything — the single
/// source of truth for "what's running" so Dashboard, Banks and Chases all
/// agree on it instead of each screen tracking its own local flag (which is
/// how a bank/chase started from one tab used to show as inactive on every
/// other tab). Also drives the small status banner shown when navigating
/// away from the Dashboard.
class NowPlaying {
  final String id;
  final PlaybackKind kind;
  final String name;

  const NowPlaying({required this.id, required this.kind, required this.name});

  bool get isBank => kind == PlaybackKind.bank;
}

final nowPlayingProvider = nowPlayingForLayerProvider(layer1Id);

/// Kills everything: every layer's player, every channel on every universe,
/// and every layer's now-playing state. Shared by the Dashboard's panic
/// button, the control dock and the remote endpoint so they can't drift
/// apart.
Future<void> blackoutEverything(ReadProvider read) async {
  // First: a held Freeze pushes its own frame over the top of everything
  // else on the way out, blackout included. The panic button has to win.
  read(momentaryFxProvider.notifier).releaseAll();
  stopSmartProgram(read);
  for (final layer in read(layersProvider)) {
    stopLayer(read, layer.id);
  }
  final service = read(artNetServiceProvider);
  if (!service.isConnected) {
    await service.connect(read(artNetSettingsProvider));
  }
  service.blackoutAll(read(universesProvider));
}

/// Stops whatever is playing without blacking the rig out — the fixtures
/// hold their current look.
void stopPlayback(ReadProvider read) {
  stopSmartProgram(read);
  for (final layer in read(layersProvider)) {
    stopLayer(read, layer.id);
  }
}

/// What last played on a given layer id before it stopped — the per-layer
/// equivalent of [lastPlayedProvider], so a live show doesn't have to re-pick
/// a bank from scratch every time a layer is stopped and restarted. Set by
/// [stopLayer] rather than tracked via a listener: a live-show restart is a
/// deliberate "put this back" action, not something that has to already be
/// watching before the very first play to avoid missing it.
final lastPlayedForLayerProvider = StateProvider.family<NowPlaying?, String>((ref, layerId) => null);

/// Stops just [layerId]'s player and clears its now-playing state, leaving
/// every other layer untouched — remembering what was running first, so
/// [resumeLayer] can bring it back. A layer the Smart Program is driving is
/// handed back from it, so the next zone change doesn't restart it.
void stopLayer(ReadProvider read, String layerId) {
  final smart = read(smartProgramPlayerProvider);
  if (smart.drives(layerId)) smart.releaseLayer(layerId);
  read(chasePlayerProvider(layerId)).stop();
  final current = read(nowPlayingForLayerProvider(layerId));
  if (current != null) {
    read(lastPlayedForLayerProvider(layerId).notifier).state = current;
  }
  read(nowPlayingForLayerProvider(layerId).notifier).state = null;
}

/// Takes [layerIds] back from the Smart Program before something else is
/// started on them. The program keeps running on its other layers.
void releaseLayersFromSmart(ReadProvider read, Iterable<String> layerIds) {
  final smart = read(smartProgramPlayerProvider);
  for (final id in layerIds) {
    if (smart.drives(id)) stopLayer(read, id);
  }
}

/// The layer ids that currently exist, Layer 1 first.
List<String> _layerIds(ReadProvider read) => [for (final l in read(layersProvider)) l.id];

/// Which layer a chase step plays on: its own layer when that still exists,
/// Layer 1 otherwise (never set, or its layer was deleted since).
String laneOf(ChaseStep step, List<String> existingLayerIds) {
  final id = step.layerId;
  return id != null && existingLayerIds.contains(id) ? id : layer1Id;
}

/// Splits [chase] into one chase per layer its steps name, in layer order —
/// each lane keeps its steps' order and plays alongside the others.
Map<String, Chase> chaseLanes(Chase chase, List<String> existingLayerIds) {
  final byLayer = <String, List<ChaseStep>>{};
  for (final step in chase.steps) {
    byLayer.putIfAbsent(laneOf(step, existingLayerIds), () => []).add(step);
  }
  return {
    for (final id in existingLayerIds)
      if (byLayer.containsKey(id)) id: chase.copyWith(steps: byLayer[id]),
  };
}

/// The layers a chase's steps play on, in layer order.
List<String> chaseLayerIds(ReadProvider read, Chase chase) =>
    chaseLanes(chase, _layerIds(read)).keys.toList();

/// Starts [chase] as parallel lanes — each layer its steps name runs its
/// own steps on its own player, all at once — and marks each started lane
/// as [playing]. Starting a lane takes its layer back from the Smart
/// Program first. Returns the layer ids that actually started (a lane whose
/// scenes/banks were all deleted flattens to nothing and doesn't).
///
/// [followBeatSync] ties the chase to the app-wide beat-sync switch for as
/// long as it runs, instead of the chase's own flag at start — flipping the
/// switch mid-chase then moves it onto or off the beat without a restart.
Future<List<String>> startLayeredChase(
  ReadProvider read,
  Chase chase, {
  required NowPlaying playing,
  Duration? Function()? fadeOverride,
  void Function(String layerId, int instantIndex)? onStep,
  bool followBeatSync = false,
}) async {
  // The players read through this on every step — see [stableRead].
  read = stableRead(read);
  final service = read(artNetServiceProvider);
  // A chase on its own beat sync steps on the beat only if the source could
  // be opened for it; otherwise it falls back to its timers.
  var ownBeatSync = false;
  if (!followBeatSync && chase.beatSync) {
    ownBeatSync = await read(activeBeatSourceProvider).start();
  }
  // A lane set to On beat opens the source itself, whatever the chase or the
  // dock say; if it can't be opened the lane falls back to its timers.
  if (chase.laneTimings.values.contains(LaneTiming.onBeat)) {
    await read(activeBeatSourceProvider).start();
  }
  // Always wired, even for a chase on its timers: a Beat Flash bank inside
  // it flashes on the beat whenever beats are coming in.
  final beatStream = read(beatPredictorProvider).events;
  final lanes = chaseLanes(chase, _layerIds(read));
  releaseLayersFromSmart(read, lanes.keys);
  final started = <String>[];
  for (final entry in lanes.entries) {
    final player = read(chasePlayerProvider(entry.key));
    final mode = chase.timingOfLane(entry.key);
    player.play(
      chase: entry.value,
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
      liveBanks: () => read(banksProvider),
      liveScenes: () => read(scenesProvider),
      liveBeatSync: switch (mode) {
        LaneTiming.free => () => false,
        LaneTiming.onBeat => () => read(activeBeatSourceProvider).isListening,
        LaneTiming.followApp => followBeatSync ? () => read(beatSyncEnabledProvider) : () => ownBeatSync,
      },
      liveBeatAvailable: mode == LaneTiming.free ? () => false : () => read(activeBeatSourceProvider).isListening,
      liveFlashGap: () => read(tempoProvider).hold,
      onStep: (index) {
        read(layerStepProvider(entry.key).notifier).state = index;
        onStep?.call(entry.key, index);
      },
      fadeOverride: mode == LaneTiming.free ? null : fadeOverride,
    );
    if (!player.isPlaying) continue;
    read(nowPlayingForLayerProvider(entry.key).notifier).state = playing;
    started.add(entry.key);
  }
  return started;
}

/// The layers currently playing [id] as a plain bank/chase (not a Smart
/// Program).
List<String> layersPlaying(ReadProvider read, String id) => [
  for (final layerId in _layerIds(read))
    if (_isPlainPlaying(read, layerId, id)) layerId,
];

bool _isPlainPlaying(ReadProvider read, String layerId, String id) {
  final np = read(nowPlayingForLayerProvider(layerId));
  return np != null &&
      np.kind != PlaybackKind.smartProgram &&
      np.id == id &&
      read(chasePlayerProvider(layerId)).isPlaying;
}

/// Stops [id] on every layer it's playing on.
void stopEverywhere(ReadProvider read, String id) {
  for (final layerId in layersPlaying(read, id)) {
    stopLayer(read, layerId);
  }
}

/// Stops the running Smart Program and clears it off every layer it drove.
void stopSmartProgram(ReadProvider read) {
  final smart = read(smartProgramPlayerProvider);
  final programId = smart.activeProgramId;
  final layerIds = smart.drivenLayerIds;
  smart.stop();
  if (programId == null) return;
  for (final layerId in {...layerIds, ..._layerIds(read)}) {
    final np = read(nowPlayingForLayerProvider(layerId));
    if (np?.kind != PlaybackKind.smartProgram || np?.id != programId) continue;
    read(lastPlayedForLayerProvider(layerId).notifier).state = np;
    read(nowPlayingForLayerProvider(layerId).notifier).state = null;
  }
}

/// Starts [program] on every layer it has targets for, replacing whatever
/// those layers were playing; other layers keep going. Returns a message
/// to report.
Future<String> startSmartProgram(ReadProvider read, SmartProgram program) async {
  final service = read(artNetServiceProvider);
  if (!service.isConnected) return 'Not connected — check Settings';
  final existing = _layerIds(read);
  final effective = program.withLayerTargets([
    for (final l in program.layers)
      if (existing.contains(l.layerId)) l,
  ]);
  if (!effective.hasAnyTarget) return '${program.name} has no chase or bank set on any layer';
  stopSmartProgram(read);
  for (final layer in effective.drivenLayers) {
    stopLayer(read, layer.layerId);
  }
  final started = await read(smartProgramPlayerProvider).start(
    program: effective,
    chases: read(chasesProvider),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: service,
  );
  if (!started) return 'Could not open the microphone for tempo tracking';
  _markSmartLayers(read, effective);
  return 'Started ${program.name}';
}

/// Points every layer the running [program] drives at it — also after an
/// edit adds a layer to a program that's already playing.
void _markSmartLayers(ReadProvider read, SmartProgram program) {
  final smart = read(smartProgramPlayerProvider);
  for (final layerId in smart.drivenLayerIds) {
    read(nowPlayingForLayerProvider(layerId).notifier).state = NowPlaying(
      id: program.id,
      kind: PlaybackKind.smartProgram,
      name: program.name,
    );
  }
}

/// Pushes an edited [program] onto the runner if it's the one playing.
void updateRunningSmartProgram(ReadProvider read, SmartProgram program) {
  final smart = read(smartProgramPlayerProvider);
  if (smart.activeProgramId != program.id) return;
  final before = smart.drivenLayerIds.toSet();
  smart.updateProgram(
    program,
    chases: read(chasesProvider),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: read(artNetServiceProvider),
  );
  // A layer the edit took off the program goes quiet and blank.
  for (final layerId in before.difference(smart.drivenLayerIds.toSet())) {
    read(chasePlayerProvider(layerId)).stop();
    read(nowPlayingForLayerProvider(layerId).notifier).state = null;
  }
  _markSmartLayers(read, program);
}

/// Re-starts whatever [lastPlayedForLayerProvider] remembers for [layerId]:
/// a bank back on this layer, a chase on all its lanes, a Smart Program on
/// all its layers. Returns a message to report.
Future<String> resumeLayer(ReadProvider read, String layerId) async {
  final last = read(lastPlayedForLayerProvider(layerId));
  if (last == null) return 'Nothing has played on this layer yet';
  switch (last.kind) {
    case PlaybackKind.bank:
      final matches = read(banksProvider).where((b) => b.id == last.id);
      if (matches.isEmpty) return 'That bank no longer exists';
      final error = runBankOnLayer(read, bank: matches.first, layerId: layerId);
      return error ?? 'Started ${matches.first.name}';
    case PlaybackKind.chase:
      final matches = read(chasesProvider).where((c) => c.id == last.id);
      if (matches.isEmpty) return 'That chase no longer exists';
      if (!read(artNetServiceProvider).isConnected) return 'Not connected — check Settings';
      final started = await startLayeredChase(
        read,
        matches.first,
        playing: NowPlaying(id: last.id, kind: PlaybackKind.chase, name: matches.first.name),
      );
      return started.isEmpty ? '${matches.first.name} has no valid steps to play' : 'Started ${matches.first.name}';
    case PlaybackKind.smartProgram:
      final matches = read(smartProgramsProvider).where((p) => p.id == last.id);
      if (matches.isEmpty) return 'That smart program no longer exists';
      return startSmartProgram(read, matches.first);
  }
}

/// Which instant (played look) each layer's player is on — for highlighting
/// the live slot, whichever screen or trigger started the layer.
final layerStepProvider = StateProvider.family<int?, String>((ref, layerId) => null);

/// The one-step chase [bank] plays as on its own: at its own Hold/Fade when
/// it has them, at the dock's otherwise.
Chase bankRunChase(ReadProvider read, Bank bank, {required String layerId}) {
  final tempo = read(tempoProvider);
  return Chase(
    id: 'bank-run-$layerId-${bank.id}',
    name: bank.name,
    steps: [
      ChaseStep(
        bankId: bank.id,
        hold: bank.ownTiming ? bank.hold : tempo.hold,
        fade: bank.ownTiming ? bank.fade : tempo.fade,
      ),
    ],
    direction: ChaseDirection.forward,
    beatSync: read(beatSyncEnabledProvider),
  );
}

/// Starts [bank] on [layerId]'s player — what "Run Bank", the layer picker,
/// a Dashboard bank tile and the remote all do. Returns an error message to
/// show the user, or null on success. A layer the Smart Program was driving
/// is taken back from it first; the program keeps its other layers.
String? runBankOnLayer(ReadProvider read, {required Bank bank, required String layerId}) {
  // The player reads through this on every step — see [stableRead].
  read = stableRead(read);
  final service = read(artNetServiceProvider);
  if (!service.isConnected) return 'Not connected — check Settings';
  releaseLayersFromSmart(read, [layerId]);
  final player = read(chasePlayerProvider(layerId));
  player.play(
    chase: bankRunChase(read, bank, layerId: layerId),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    patchedFixtures: read(patchedFixturesProvider),
    universes: read(universesProvider),
    service: service,
    beatStream: read(beatPredictorProvider).events,
    liveBeatSync: () => read(beatSyncEnabledProvider),
    liveBeatAvailable: () => read(activeBeatSourceProvider).isListening,
    liveFlashGap: () => bank.ownTiming ? bank.hold : read(tempoProvider).hold,
    beatRate: read(beatRateProvider),
    flashLength: read(flashLengthProvider),
    liveBeatRate: () => read(beatRateProvider),
    liveFlashLength: () => read(flashLengthProvider),
    liveBanks: () => read(banksProvider),
    liveScenes: () => read(scenesProvider),
    // Auto-fade is the dock's; a bank keeping its own timing keeps its own
    // fade too.
    fadeOverride: bank.ownTiming
        ? null
        : () {
            final t = read(tempoProvider);
            return t.autoFade ? t.fade : null;
          },
    onStep: (index) => read(layerStepProvider(layerId).notifier).state = index,
  );
  // A bank with every slot empty flattens to zero steps, and `play` quietly
  // declines to run them — reporting it as playing would leave nowPlaying
  // claiming a run that never started.
  if (!player.isPlaying) return '"${bank.name}" has no filled slots to play';
  read(nowPlayingForLayerProvider(layerId).notifier).state = NowPlaying(
    id: bank.id,
    kind: PlaybackKind.bank,
    name: bank.name,
  );
  return null;
}

/// Re-starts [bankId] on every layer it's playing on, so an edit to its
/// timing lands straight away.
void restartBankEverywhere(ReadProvider read, String bankId) {
  final banks = read(banksProvider).where((b) => b.id == bankId);
  if (banks.isEmpty) return;
  for (final layerId in layersPlaying(read, bankId)) {
    runBankOnLayer(read, bank: banks.first, layerId: layerId);
  }
}

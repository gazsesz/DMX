import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/smart_layer_display.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/remote/trigger_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/play_toggle_card.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/layer_badge.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../core/widgets/show_items_actions.dart';
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/smart_program.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/tempo_providers.dart';
import 'chase_editor_screen.dart';
import '../songs/song_shows_section.dart';
import 'smart_program_editor_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/status_messages.dart';

class ChasesScreen extends ConsumerStatefulWidget {
  const ChasesScreen({super.key});

  @override
  ConsumerState<ChasesScreen> createState() => _ChasesScreenState();
}

class _ChasesScreenState extends ConsumerState<ChasesScreen> {
  /// Always the current runner. The provider builds a new one when the beat
  /// source changes (mic ↔ MIDI ↔ rkbx_link), and this screen lives on in the
  /// shell's IndexedStack — holding the first one meant it showed a program
  /// started afterwards as not running, and its Start button acted on a
  /// player nobody used any more.
  SmartProgramPlayer get _smartPlayer => ref.read(smartProgramPlayerProvider);
  SmartProgramStatus? _smartStatus;
  StreamSubscription<SmartProgramStatus>? _smartStatusSub;

  @override
  void initState() {
    super.initState();
    // The stream only carries changes — see the Dashboard, which shows the
    // same zone readout.
    _smartStatus = ref.read(smartProgramStatusProvider).valueOrNull;
    ref.listenManual<SmartProgramPlayer>(smartProgramPlayerProvider, (previous, player) {
      _smartStatusSub?.cancel();
      _smartStatusSub = player.statusStream.listen((status) {
        if (mounted) setState(() => _smartStatus = status);
      });
      if (previous != null && mounted) setState(() => _smartStatus = null);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _smartStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _open(Chase chase) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChaseEditorScreen(existing: chase)));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeStatus(message, context.l10n))));
  }

  Future<void> _togglePlay(Chase chase) async {
    if (layersPlaying(ref.read, chase.id).isNotEmpty) {
      stopEverywhere(ref.read, chase.id);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      _snack(context.l10n.wNotConnectedCheckSettings);
      return;
    }
    // This screen used to call the player raw — no beat stream, no beat
    // rate, no flash length — so Beat Sync and the Flash rate did nothing
    // to a chase fired from the list, while the very same chase beat-synced
    // fine from the Dashboard or the Banks screen. It goes through the one
    // shared start now, like every other trigger in the app.
    if (chase.beatSync && !ref.read(beatSyncEnabledProvider)) {
      // The chase asks for the beat itself: arm the app-wide switch rather
      // than run the mic behind the dock's back, so what the dock shows and
      // what the rig does stay the same thing.
      final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(true);
      if (error != null) _snack(context.l10n.wFallingBackToTimed(error));
    }
    if (!mounted) return;
    final started = await startChase(
      ref.read,
      chaseAsDashboardPlaysIt(ref.read, chase),
      playing: NowPlaying(id: chase.id, kind: PlaybackKind.chase, name: chase.name),
      dashboardTiming: ref.read(tempoProvider).overrideTiming,
      exclusive: true,
    );
    // A step whose scene or bank was since deleted flattens to nothing, and
    // the player quietly declines to run zero steps.
    if (started.isEmpty) _snack(context.l10n.wHasNoValidSteps(chase.name));
  }

  Future<void> _toggleSmartProgram(SmartProgram program) async {
    final wasRunning = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
    final message = await toggleSmartProgramById(ref.read, program.id);
    if (!mounted) return;
    if (wasRunning) setState(() => _smartStatus = null);
    if (!message.startsWith('Started') && !message.startsWith('Stopped')) _snack(message);
  }

  Future<void> _newSmartProgram() async {
    final program = ref.read(smartProgramsProvider.notifier).create(context.l10n.wNewSmartProgram);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program)));
  }

  Future<void> _deleteChase(Chase chase) async {
    final usedBy = [
      for (final program in ref.read(smartProgramsProvider))
        if (program.usesChase(chase.id)) program.name,
    ];
    final confirmed = await confirmDelete(
      context,
      title: context.l10n.layersDeleteTitle(chase.name),
      message: [
        context.l10n.chaseDeleteStepsGo(chase.steps.length),
        if (usedBy.isNotEmpty)
          'Used by ${usedBy.length == 1 ? 'the smart program' : 'smart programs'} '
              '${usedBy.join(', ')} — that zone will fall back to the base one.',
      ].join('\n\n'),
    );
    if (!confirmed) return;
    stopEverywhere(ref.read, chase.id);
    ref.read(chasesProvider.notifier).remove(chase.id);
  }

  Future<void> _deleteProgram(SmartProgram program) async {
    final confirmed = await confirmDelete(
      context,
      title: context.l10n.layersDeleteTitle(program.name),
      message: context.l10n.wTheChasesAndBanks,
    );
    if (!confirmed) return;
    if (_smartPlayer.activeProgramId == program.id) stopSmartProgram(ref.read);
    ref.read(smartProgramsProvider.notifier).remove(program.id);
  }

  /// One layer's line in a Smart Program card.
  Widget _smartLine(SmartLayerLine line, {required bool active}) {
    final String text;
    if (line.targetName != null) {
      text = line.targetName!;
    } else if (line.onlyIn != null && line.onlyIn!.isNotEmpty) {
      text = context.l10n.wOnly(line.onlyIn!);
    } else {
      text = context.l10n.wEmptyNow;
    }
    final zone = line.sourceZone;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          LayerBadge(index: line.layerIndex, dim: line.targetName == null),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: line.targetName == null ? AppColors.textFaint : AppColors.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (active && zone != null)
            Text(
              zoneLabel(zone).toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: zone == SmartProgramZone.base ? AppColors.textFaint : AppColors.accent2,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chases = ref.watch(chasesProvider);
    final banks = ref.watch(banksProvider);
    final smartPrograms = ref.watch(smartProgramsProvider);
    final layers = ref.watch(layersProvider);
    // Watched so a chase started or stopped on any layer — from here or
    // anywhere else — redraws its row.
    for (final layer in layers) {
      ref.watch(nowPlayingForLayerProvider(layer.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.wChases),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: context.l10n.wImportChasesBanks,
            onPressed: () => importShowItemsFromFile(context, ref),
          ),
          const NodeStatusAction(),
          const ControlDockAction(),
          const SaveProjectAction(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.dashSmartProgramsHeader,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textFaint,
                  letterSpacing: 1,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: context.l10n.wNewSmartProgram,
                onPressed: _newSmartProgram,
              ),
            ],
          ),
          Text(
            context.l10n.wSwitchesEachLayerBetween,
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          if (smartPrograms.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(context.l10n.wNoSmartProgramsYet, style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            )
          else
            for (final program in smartPrograms) ...[
              Builder(
                builder: (context) {
                  final active = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
                  final status = active ? _smartStatus : null;
                  final zone = active ? (status?.zone ?? _smartPlayer.currentZone) : null;
                  final zoneText = status?.isSilent == true
                      ? context.l10n.wNoMusic
                      : zoneLabel(zone ?? SmartProgramZone.base).toUpperCase();
                  final lines = smartLayerLines(program, zone: zone, layers: layers, chases: chases, banks: banks);
                  return PlayToggleCard(
                    active: active,
                    icon: Icons.auto_graph,
                    accent: AppColors.accent2,
                    accentOn: AppColors.accent2On,
                    toggleKey: ValueKey('smart-toggle-${program.id}'),
                    onToggle: () => _toggleSmartProgram(program),
                    onOpen: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                program.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: active ? AppColors.accent2 : null,
                                ),
                              ),
                              Text(
                                active
                                    ? context.l10n.smartZoneLine(zoneText, status?.liveBpm != null ? context.l10n.smartLiveBpm(status!.liveBpm!.round()) : '')
                                    : context.l10n.wBpmBase(program.baseBpm.round()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: active ? AppColors.accent2 : AppColors.textFaint,
                                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                              if (lines.isEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    context.l10n.wNothingSetYetTap,
                                    style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                                  ),
                                ),
                              for (final line in lines) _smartLine(line, active: active),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () => ref.read(smartProgramsProvider.notifier).duplicate(program.id),
                          tooltip: context.l10n.scDuplicate,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteProgram(program),
                          tooltip: context.l10n.scDelete,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          const SizedBox(height: 20),
          const SongShowsSection(),
          const SizedBox(height: 20),
          Text(
            context.l10n.dashChasesHeader,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          if (chases.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(context.l10n.wNoChasesYetTap, style: TextStyle(color: AppColors.textFaint)),
            )
          else
            for (final chase in chases) ...[
              Builder(
                builder: (context) {
                  final active = layersPlaying(ref.read, chase.id).isNotEmpty;
                  final layerIds = chaseLayerIds(ref.read, chase);
                  // Lanes another layer's run has taken over (a Smart Program on
                  // Layer 1, say) are dimmed: the chase still runs on the rest.
                  final runningLayers = layersPlaying(ref.read, chase.id).toSet();
                  final onDashboard = ref
                      .watch(dashboardTriggersProvider)
                      .any((t) => t.id == chase.id && t.kind == TriggerKind.chase);
                  return PlayToggleCard(
                    active: active,
                    icon: Icons.fast_forward_outlined,
                    accent: AppColors.accent,
                    accentOn: AppColors.accentOn,
                    toggleKey: ValueKey('chase-toggle-${chase.id}'),
                    onToggle: () => _togglePlay(chase),
                    onOpen: () => _open(chase),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(chase.name, style: TextStyle(fontSize: 15, color: active ? AppColors.accent : null)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      active
                                          ? (runningLayers.length < layerIds.length
                                                ? context.l10n.wRunningOnOfLayers(runningLayers.length, layerIds.length)
                                                : context.l10n.wRunning)
                                          : context.l10n.wStepsSStep(chase.steps.length, chase.stepSeconds.toStringAsFixed(2)),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: active ? AppColors.accent : AppColors.textFaint,
                                        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  for (final id in layerIds) ...[
                                    const SizedBox(width: 5),
                                    Opacity(
                                      opacity: !active || runningLayers.contains(id) ? 1 : 0.3,
                                      child: LayerBadge(index: layers.indexWhere((l) => l.id == id), small: true),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            onDashboard ? Icons.dashboard : Icons.dashboard_customize_outlined,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            hoverColor: AppColors.accent.withValues(alpha: 0.15),
                            highlightColor: AppColors.accent.withValues(alpha: 0.25),
                          ),
                          tooltip: onDashboard ? context.l10n.banksRemoveFromDashboard : context.l10n.banksAddToDashboard,
                          onPressed: () {
                            final notifier = ref.read(dashboardTriggersProvider.notifier);
                            notifier.toggle(chase.id, TriggerKind.chase);
                            _snack(
                              onDashboard
                                  ? context.l10n.banksRemovedFromDashboard(chase.name)
                                  : context.l10n.banksAddedToDashboard(chase.name),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () => ref.read(chasesProvider.notifier).duplicate(chase.id),
                          tooltip: context.l10n.scDuplicate,
                        ),
                        IconButton(
                          icon: const Icon(Icons.upload_file, size: 18),
                          onPressed: () => exportShowItemsToFile(context, ref, chaseIds: [chase.id]),
                          tooltip: context.l10n.wExportWithItsBanks,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteChase(chase),
                          tooltip: context.l10n.scDelete,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'chases-fab',
        onPressed: () async {
          final chase = ref.read(chasesProvider.notifier).create(context.l10n.wNewChase);
          await _open(chase);
        },
        tooltip: context.l10n.wNewChase,
        child: const Icon(Icons.add),
      ),
    );
  }
}

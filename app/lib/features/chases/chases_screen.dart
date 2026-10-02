import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/smart_layer_display.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/remote/trigger_actions.dart';
import '../../core/theme/app_colors.dart';
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
import 'smart_program_editor_screen.dart';

class ChasesScreen extends ConsumerStatefulWidget {
  const ChasesScreen({super.key});

  @override
  ConsumerState<ChasesScreen> createState() => _ChasesScreenState();
}

class _ChasesScreenState extends ConsumerState<ChasesScreen> {
  late final SmartProgramPlayer _smartPlayer;
  SmartProgramStatus? _smartStatus;
  StreamSubscription<SmartProgramStatus>? _smartStatusSub;

  @override
  void initState() {
    super.initState();
    _smartPlayer = ref.read(smartProgramPlayerProvider);
    // The stream only carries changes — see the Dashboard, which shows the
    // same zone readout.
    _smartStatus = ref.read(smartProgramStatusProvider).valueOrNull;
    _smartStatusSub = _smartPlayer.statusStream.listen((status) {
      if (mounted) setState(() => _smartStatus = status);
    });
  }

  @override
  void dispose() {
    _smartStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _open(Chase chase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChaseEditorScreen(existing: chase)),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePlay(Chase chase) async {
    if (layersPlaying(ref.read, chase.id).isNotEmpty) {
      stopEverywhere(ref.read, chase.id);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      _snack('Not connected — check Settings');
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
      if (error != null) _snack('$error — falling back to timed steps');
    }
    if (!mounted) return;
    final started = await startChase(
      ref.read,
      chaseAsDashboardPlaysIt(ref.read, chase),
      playing: NowPlaying(id: chase.id, kind: PlaybackKind.chase, name: chase.name),
      dashboardTiming: ref.read(tempoProvider).overrideTiming,
    );
    // A step whose scene or bank was since deleted flattens to nothing, and
    // the player quietly declines to run zero steps.
    if (started.isEmpty) _snack('"${chase.name}" has no valid steps — check its scenes/banks still exist');
  }

  Future<void> _toggleSmartProgram(SmartProgram program) async {
    final wasRunning = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
    final message = await toggleSmartProgramById(ref.read, program.id);
    if (!mounted) return;
    if (wasRunning) setState(() => _smartStatus = null);
    if (!message.startsWith('Started') && !message.startsWith('Stopped')) _snack(message);
  }

  Future<void> _newSmartProgram() async {
    final program = ref.read(smartProgramsProvider.notifier).create('New Smart Program');
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program)),
    );
  }

  Future<void> _deleteChase(Chase chase) async {
    final usedBy = [
      for (final program in ref.read(smartProgramsProvider))
        if (program.usesChase(chase.id)) program.name,
    ];
    final confirmed = await confirmDelete(
      context,
      title: 'Delete "${chase.name}"?',
      message: [
        'Its ${chase.steps.length} ${chase.steps.length == 1 ? 'step' : 'steps'} go with it. '
            'The scenes and banks it stepped through stay in the project.',
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
      title: 'Delete "${program.name}"?',
      message: 'The chases and banks it switches between stay in the project.',
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
      text = '— (csak ${line.onlyIn})';
    } else {
      text = '— most üres';
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
        title: const Text('Chases'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import chases / banks',
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
              const Text(
                'SMART PROGRAMS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'New Smart Program',
                onPressed: _newSmartProgram,
              ),
            ],
          ),
          const Text(
            'Switches each layer between its own chases as the live music tempo speeds up or slows down',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          if (smartPrograms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No smart programs yet', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            )
          else
            for (final program in smartPrograms) ...[
              Builder(
                builder: (context) {
                  final active = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
                  final status = active ? _smartStatus : null;
                  final zone = active ? (status?.zone ?? _smartPlayer.currentZone) : null;
                  final zoneText = status?.isSilent == true
                      ? 'NO MUSIC'
                      : zoneLabel(zone ?? SmartProgramZone.base).toUpperCase();
                  final lines = smartLayerLines(program, zone: zone, layers: layers, chases: chases, banks: banks);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: active ? AppColors.accent2.withValues(alpha: 0.1) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: active ? AppColors.accent2 : Colors.transparent, width: 1.5),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _toggleSmartProgram(program),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active ? AppColors.accent2 : AppColors.panel2,
                                ),
                                child: Icon(
                                  active ? Icons.stop_rounded : Icons.auto_graph,
                                  color: active ? AppColors.accent2On : AppColors.accent2,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                        ? 'Zone $zoneText${status?.liveBpm != null ? ' · ${status!.liveBpm!.round()} BPM live' : ''}'
                                        : '${program.baseBpm.round()} BPM base',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: active ? AppColors.accent2 : AppColors.textFaint,
                                      fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                    ),
                                  ),
                                  if (lines.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Nothing set yet — tap to pick chases per layer',
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
                              tooltip: 'Duplicate',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _deleteProgram(program),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          const SizedBox(height: 20),
          const Text(
            'CHASES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          if (chases.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No chases yet — tap + to create one', style: TextStyle(color: AppColors.textFaint)),
            )
          else
            for (final chase in chases) ...[
              Builder(
                builder: (context) {
                  final active = layersPlaying(ref.read, chase.id).isNotEmpty;
                  final layerIds = chaseLayerIds(ref.read, chase);
                  final onDashboard = ref
                      .watch(dashboardTriggersProvider)
                      .any((t) => t.id == chase.id && t.kind == TriggerKind.chase);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: active ? AppColors.accent.withValues(alpha: 0.1) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: active ? AppColors.accent : Colors.transparent, width: 1.5),
                    ),
                    child: ListTile(
                      leading: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _togglePlay(chase),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active ? AppColors.accent : AppColors.panel2,
                          ),
                          child: Icon(
                            active ? Icons.stop_rounded : Icons.fast_forward_outlined,
                            color: active ? AppColors.accentOn : AppColors.accent,
                            size: 20,
                          ),
                        ),
                      ),
                      title: Text(chase.name, style: TextStyle(color: active ? AppColors.accent : null)),
                      subtitle: Row(
                        children: [
                          Flexible(
                            child: Text(
                              active
                                  ? 'Running…'
                                  : '${chase.steps.length} steps · ${chase.stepSeconds.toStringAsFixed(2)}s/step',
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
                            LayerBadge(index: layers.indexWhere((l) => l.id == id), small: true),
                          ],
                        ],
                      ),
                      onTap: () => _open(chase),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                            tooltip: onDashboard ? 'Remove from Dashboard' : 'Add to Dashboard',
                            onPressed: () {
                              final notifier = ref.read(dashboardTriggersProvider.notifier);
                              notifier.toggle(chase.id, TriggerKind.chase);
                              _snack(onDashboard ? 'Removed "${chase.name}" from Dashboard' : 'Added "${chase.name}" to Dashboard');
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            onPressed: () => ref.read(chasesProvider.notifier).duplicate(chase.id),
                            tooltip: 'Duplicate',
                          ),
                          IconButton(
                            icon: const Icon(Icons.upload_file, size: 18),
                            onPressed: () => exportShowItemsToFile(context, ref, chaseIds: [chase.id]),
                            tooltip: 'Export (with its banks and scenes)',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteChase(chase),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
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
          final chase = ref.read(chasesProvider.notifier).create('New Chase');
          await _open(chase);
        },
        tooltip: 'New Chase',
        child: const Icon(Icons.add),
      ),
    );
  }
}

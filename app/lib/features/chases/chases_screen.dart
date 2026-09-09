import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/smart_program.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';
import 'chase_editor_screen.dart';
import 'smart_program_editor_screen.dart';

class ChasesScreen extends ConsumerStatefulWidget {
  const ChasesScreen({super.key});

  @override
  ConsumerState<ChasesScreen> createState() => _ChasesScreenState();
}

class _ChasesScreenState extends ConsumerState<ChasesScreen> {
  late final ChasePlayer _player;
  late final SmartProgramPlayer _smartPlayer;
  SmartProgramStatus? _smartStatus;
  StreamSubscription<SmartProgramStatus>? _smartStatusSub;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider);
    _smartPlayer = ref.read(smartProgramPlayerProvider);
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

  Future<void> _togglePlay(Chase chase) async {
    final current = ref.read(nowPlayingProvider);
    final isThisActive = _player.isPlaying && current?.kind == PlaybackKind.chase && current?.id == chase.id;
    if (isThisActive) {
      _player.stop();
      ref.read(nowPlayingProvider.notifier).state = null;
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    _smartPlayer.stop();
    _player.play(
      chase: chase,
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
      onStep: (_) {},
    );
    ref.read(nowPlayingProvider.notifier).state = NowPlaying(
      id: chase.id,
      kind: PlaybackKind.chase,
      name: chase.name,
    );
  }

  Future<void> _toggleSmartProgram(SmartProgram program) async {
    if (_smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id) {
      _smartPlayer.stop();
      setState(() => _smartStatus = null);
      ref.read(nowPlayingProvider.notifier).state = null;
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    if (!program.hasBaseTarget) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a base chase or bank for this program first')),
      );
      return;
    }
    _player.stop();
    ref.read(nowPlayingProvider.notifier).state = null;
    final started = await _smartPlayer.start(
      program: program,
      chases: ref.read(chasesProvider),
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
    );
    if (started) {
      ref.read(nowPlayingProvider.notifier).state = NowPlaying(
        id: program.id,
        kind: PlaybackKind.smartProgram,
        name: program.name,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the microphone for tempo tracking')),
      );
    }
  }

  Future<void> _newSmartProgram() async {
    final program = ref.read(smartProgramsProvider.notifier).create('New Smart Program');
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program)),
    );
  }

  /// Display name for whatever a Smart Program zone points at — chase or bank.
  String _targetName(ProgramTarget? target) {
    if (target == null) return '—';
    if (target.isBank) {
      final matches = ref.read(banksProvider).where((b) => b.id == target.id);
      return matches.isEmpty ? 'Missing bank' : matches.first.name;
    }
    final matches = ref.read(chasesProvider).where((c) => c.id == target.id);
    return matches.isEmpty ? 'Missing chase' : matches.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final chases = ref.watch(chasesProvider);
    final smartPrograms = ref.watch(smartProgramsProvider);
    final nowPlaying = ref.watch(nowPlayingProvider);
    final isPlaying = _player.isPlaying;

    return Scaffold(
      appBar: AppBar(title: const Text('Chases'), actions: const [ControlDockAction(), SaveProjectAction()]),
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
            'Switches between chases as the live music tempo speeds up or slows down',
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
                  final zoneLabel = status?.isSilent == true
                      ? 'NO MUSIC'
                      : switch (status?.zone) {
                          SmartProgramZone.faster => 'FASTER',
                          SmartProgramZone.slower => 'SLOWER',
                          _ => 'BASE',
                        };
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: active ? AppColors.accent2.withValues(alpha: 0.1) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: active ? AppColors.accent2 : Colors.transparent, width: 1.5),
                    ),
                    child: ListTile(
                      leading: InkWell(
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
                      title: Text(program.name, style: TextStyle(color: active ? AppColors.accent2 : null)),
                      subtitle: active
                          ? Text(
                              'Zone: $zoneLabel'
                              '${status?.liveBpm != null ? ' · ${status!.liveBpm!.round()} BPM live' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppColors.accent2, fontWeight: FontWeight.w700),
                            )
                          : Text(
                              'Base ${_targetName(program.baseTarget)}'
                              '${program.fasterTarget != null ? ' · Faster ${_targetName(program.fasterTarget)}' : ''}'
                              '${program.slowerTarget != null ? ' · Slower ${_targetName(program.slowerTarget)}' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SmartProgramEditorScreen(existing: program)),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            onPressed: () => ref.read(smartProgramsProvider.notifier).duplicate(program.id),
                            tooltip: 'Duplicate',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => ref.read(smartProgramsProvider.notifier).remove(program.id),
                            tooltip: 'Delete',
                          ),
                        ],
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
                  final active = isPlaying && nowPlaying?.kind == PlaybackKind.chase && nowPlaying?.id == chase.id;
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
                      subtitle: Text(
                        active
                            ? 'Running…'
                            : '${chase.steps.length} steps · ${chase.stepSeconds.toStringAsFixed(2)}s/step',
                        style: TextStyle(
                          fontSize: 11,
                          color: active ? AppColors.accent : AppColors.textFaint,
                          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                        ),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    onDashboard
                                        ? 'Removed "${chase.name}" from Dashboard'
                                        : 'Added "${chase.name}" to Dashboard',
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            onPressed: () => ref.read(chasesProvider.notifier).duplicate(chase.id),
                            tooltip: 'Duplicate',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => ref.read(chasesProvider.notifier).remove(chase.id),
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

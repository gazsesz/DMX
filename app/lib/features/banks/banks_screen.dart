import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/playback/scene_output.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/scene_providers.dart';
import 'program_generator_screen.dart';

class BanksScreen extends ConsumerStatefulWidget {
  const BanksScreen({super.key});

  @override
  ConsumerState<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends ConsumerState<BanksScreen> {
  String? _selectedBankId;
  late final ChasePlayer _player;
  double _runHoldSeconds = 0.8;
  double _runFadeSeconds = 0.3;
  int? _runningSlot;

  /// The slot the user last fired by hand — so tapping a scene shows which
  /// one is live even when the bank isn't running as a chase.
  int? _manualSlot;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider);
  }

  bool _isThisBankRunning(Bank bank) {
    final current = ref.read(nowPlayingProvider);
    return _player.isPlaying && current?.kind == PlaybackKind.bank && current?.id == bank.id;
  }

  void _toggleRun(Bank bank) {
    if (_isThisBankRunning(bank)) {
      _player.stop();
      ref.read(nowPlayingProvider.notifier).state = null;
      setState(() => _runningSlot = null);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    ref.read(smartProgramPlayerProvider).stop();
    final beatSync = ref.read(beatSyncEnabledProvider);
    final chase = Chase(
      id: 'bank-run-${bank.id}',
      name: bank.name,
      steps: [
        ChaseStep(
          bankId: bank.id,
          hold: Duration(milliseconds: (_runHoldSeconds * 1000).round()),
          fade: Duration(milliseconds: (_runFadeSeconds * 1000).round()),
        ),
      ],
      direction: ChaseDirection.forward,
      beatSync: beatSync,
    );
    _player.play(
      chase: chase,
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
      beatStream: beatSync ? ref.read(beatDetectorProvider).beatEvents : null,
      onStep: (index) {
        if (mounted) setState(() => _runningSlot = index);
      },
    );
    ref.read(nowPlayingProvider.notifier).state = NowPlaying(
      id: bank.id,
      kind: PlaybackKind.bank,
      name: bank.name,
    );
    setState(() => _manualSlot = null);
  }

  Future<void> _setBeatSync(bool value) async {
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Re-arm whatever is running so it picks up (or drops) beat stepping
    // right away instead of only on the next run.
    final banks = ref.read(banksProvider);
    final running = banks.where(_isThisBankRunning);
    if (running.isNotEmpty) {
      final bank = running.first;
      _player.stop();
      _toggleRun(bank);
    }
  }

  void _restartRunIfPlaying(Bank bank) {
    if (!_isThisBankRunning(bank)) return;
    _player.stop();
    _toggleRun(bank);
  }

  Future<void> _pickScene(Bank bank, int slotIndex) async {
    final scenes = ref.read(scenesProvider);
    if (scenes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a scene first')),
      );
      return;
    }
    final chosen = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: Text('Slot ${slotIndex + 1}'),
        children: [
          if (bank.sceneSlots[slotIndex] != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear slot', style: TextStyle(color: AppColors.danger)),
            ),
          for (final scene in scenes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, scene.id),
              child: Text(scene.name),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    ref.read(banksProvider.notifier).setSlot(bank.id, slotIndex, chosen.isEmpty ? null : chosen);
  }

  void _playSlot(Bank bank, int slotIndex) {
    final sceneId = bank.sceneSlots[slotIndex];
    if (sceneId == null) return;
    final scenes = ref.read(scenesProvider);
    final matches = scenes.where((s) => s.id == sceneId);
    if (matches.isEmpty) return;
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    outputScene(
      service: service,
      scene: matches.first,
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
    );
    setState(() => _manualSlot = slotIndex);
  }

  Future<void> _renameBank(Bank bank) async {
    final controller = TextEditingController(text: bank.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Rename Bank'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      ref.read(banksProvider.notifier).rename(bank.id, controller.text.trim());
    }
  }

  Future<void> _resizeBank(Bank bank) async {
    final controller = TextEditingController(text: bank.sceneSlots.length.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Bank Size'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Number of slots'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final size = int.tryParse(controller.text);
    if (result == true && size != null && size > 0) {
      ref.read(banksProvider.notifier).resize(bank.id, size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final scenes = ref.watch(scenesProvider);
    if (banks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Banks'), actions: const [SaveProjectAction()]),
        body: const Center(child: Text('No banks yet', style: TextStyle(color: AppColors.textFaint))),
      );
    }
    final selected = banks.firstWhere(
      (b) => b.id == _selectedBankId,
      orElse: () => banks.first,
    );
    final nowPlaying = ref.watch(nowPlayingProvider);
    final isRunningThisBank =
        _player.isPlaying && nowPlaying?.kind == PlaybackKind.bank && nowPlaying?.id == selected.id;
    final beatSync = ref.watch(beatSyncEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate Program',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgramGeneratorScreen()),
            ),
          ),
          Builder(builder: (context) {
            final onDashboard = ref
                .watch(dashboardTriggersProvider)
                .any((t) => t.id == selected.id && t.kind == TriggerKind.bank);
            return IconButton(
              icon: Icon(onDashboard ? Icons.dashboard : Icons.dashboard_customize_outlined, color: AppColors.accent),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.accent,
                hoverColor: AppColors.accent.withValues(alpha: 0.15),
                highlightColor: AppColors.accent.withValues(alpha: 0.25),
              ),
              tooltip: onDashboard ? 'Remove from Dashboard' : 'Add to Dashboard',
              onPressed: () {
                final notifier = ref.read(dashboardTriggersProvider.notifier);
                notifier.toggle(selected.id, TriggerKind.bank);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      onDashboard
                          ? 'Removed "${selected.name}" from Dashboard'
                          : 'Added "${selected.name}" to Dashboard',
                    ),
                  ),
                );
              },
            );
          }),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename bank',
            onPressed: () => _renameBank(selected),
          ),
          const SaveProjectAction(),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final bank in banks)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(bank.name),
                      selected: bank.id == selected.id,
                      onSelected: (_) {
                        if (_isThisBankRunning(selected)) {
                          _player.stop();
                          ref.read(nowPlayingProvider.notifier).state = null;
                        }
                        setState(() {
                          _selectedBankId = bank.id;
                          _runningSlot = null;
                          _manualSlot = null;
                        });
                      },
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                  onPressed: () {
                    final newBank = ref.read(banksProvider.notifier).addBank();
                    setState(() => _selectedBankId = newBank.id);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bank Size: ${selected.sceneSlots.length} slots',
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
                TextButton(onPressed: () => _resizeBank(selected), child: const Text('Edit Size')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _toggleRun(selected),
                  icon: Icon(isRunningThisBank ? Icons.stop : Icons.play_arrow),
                  label: Text(isRunningThisBank ? 'Stop' : 'Run Bank'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: beatSync ? 'Beat Sync on — steps wait for the beat' : 'Beat Sync off — steps on the timer',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_none,
                        size: 16,
                        color: beatSync ? AppColors.accent : AppColors.textFaint,
                      ),
                      Switch(
                        value: beatSync,
                        onChanged: _setBeatSync,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Hold ${_runHoldSeconds.toStringAsFixed(2)}s · Fade ${_runFadeSeconds.toStringAsFixed(2)}s',
                        style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _runHoldSeconds,
                              min: 0,
                              max: 5,
                              onChanged: (v) => setState(() => _runHoldSeconds = v),
                              onChangeEnd: (_) => _restartRunIfPlaying(selected),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _runFadeSeconds,
                              min: 0,
                              max: 5,
                              activeColor: AppColors.accent2,
                              onChanged: (v) => setState(() => _runFadeSeconds = v),
                              onChangeEnd: (_) => _restartRunIfPlaying(selected),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(builder: (context) {
              final filledIndices = [
                for (var i = 0; i < selected.sceneSlots.length; i++)
                  if (selected.sceneSlots[i] != null) i,
              ];
              final highlightIndex =
                  (isRunningThisBank && _runningSlot != null && _runningSlot! < filledIndices.length)
                      ? filledIndices[_runningSlot!]
                      : null;
              return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: selected.sceneSlots.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 76,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final sceneId = selected.sceneSlots[index];
                final scene = sceneId == null
                    ? null
                    : scenes.where((s) => s.id == sceneId).firstOrNull;
                // Highlight the step the chase is on while the bank runs, and
                // otherwise the slot the user last fired by hand.
                final isRunning = isRunningThisBank
                    ? index == highlightIndex
                    : scene != null && index == _manualSlot;
                return Stack(
                  children: [
                    InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => scene == null ? _pickScene(selected, index) : _playSlot(selected, index),
                  onLongPress: () => _pickScene(selected, index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isRunning ? AppColors.accent.withValues(alpha: 0.14) : AppColors.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRunning ? AppColors.accent : AppColors.border,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          scene == null ? Icons.add : Icons.play_circle_outline,
                          size: 13,
                          color: scene == null ? AppColors.textFaint : AppColors.accent,
                        ),
                        if (scene != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            scene.name,
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        Text('${index + 1}', style: const TextStyle(fontSize: 7, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                    ),
                    if (scene != null)
                      Positioned(
                        top: 1,
                        right: 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => _pickScene(selected, index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, size: 10, color: AppColors.textDim),
                          ),
                        ),
                      ),
                  ],
                );
              },
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(banksProvider.notifier).duplicate(selected.id),
                    child: const Text('Duplicate Bank'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: banks.length <= 1
                        ? null
                        : () {
                            ref.read(banksProvider.notifier).remove(selected.id);
                            setState(() => _selectedBankId = null);
                          },
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Delete Bank'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

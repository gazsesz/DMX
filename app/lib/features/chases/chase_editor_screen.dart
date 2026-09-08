import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chase.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';

class ChaseEditorScreen extends ConsumerStatefulWidget {
  final Chase existing;

  const ChaseEditorScreen({super.key, required this.existing});

  @override
  ConsumerState<ChaseEditorScreen> createState() => _ChaseEditorScreenState();
}

class _ChaseEditorScreenState extends ConsumerState<ChaseEditorScreen> {
  late TextEditingController _nameController;
  late List<ChaseStep> _steps;
  late double _stepSeconds;
  double _defaultFadeSeconds = 0.3;
  late bool _beatSync;
  late ChaseDirection _direction;
  final _player = ChasePlayer();
  int? _playingIndex;
  final Set<int> _expandedBankSteps = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing.name);
    _steps = [...widget.existing.steps];
    _stepSeconds = widget.existing.stepSeconds;
    _beatSync = widget.existing.beatSync;
    _direction = widget.existing.direction;
  }

  @override
  void dispose() {
    _player.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addStep({required bool asBank}) async {
    final options = asBank ? ref.read(banksProvider) : ref.read(scenesProvider);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create a ${asBank ? 'bank' : 'scene'} first')),
      );
      return;
    }
    final chosenId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: Text('Add ${asBank ? 'Bank' : 'Scene'} Step'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (option as dynamic).id as String),
              child: Text((option as dynamic).name as String),
            ),
        ],
      ),
    );
    if (chosenId == null) return;
    final hold = Duration(milliseconds: (_stepSeconds * 1000).round());
    final fade = Duration(milliseconds: (_defaultFadeSeconds * 1000).round());
    setState(() {
      _steps.add(
        asBank
            ? ChaseStep(bankId: chosenId, hold: hold, fade: fade)
            : ChaseStep(sceneId: chosenId, hold: hold, fade: fade),
      );
    });
  }

  void _applyHoldToAllSteps() {
    final hold = Duration(milliseconds: (_stepSeconds * 1000).round());
    _steps = [
      for (final step in _steps)
        ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: hold, fade: step.fade),
    ];
  }

  void _applyFadeToAllSteps() {
    final fade = Duration(milliseconds: (_defaultFadeSeconds * 1000).round());
    _steps = [
      for (final step in _steps)
        ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: step.hold, fade: fade),
    ];
  }

  void _restartIfPlaying() {
    if (!_player.isPlaying) return;
    _player.stop();
    _togglePreview();
  }

  void _removeStep(int index) {
    setState(() => _steps.removeAt(index));
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(target, step);
    });
  }

  Future<void> _editStepTiming(int index) async {
    final step = _steps[index];
    var hold = step.hold.inMilliseconds / 1000.0;
    var fade = step.fade.inMilliseconds / 1000.0;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Step Timing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hold: ${hold.toStringAsFixed(2)}s', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              Slider(value: hold, min: 0, max: 10, onChanged: (v) => setDialogState(() => hold = v)),
              const SizedBox(height: 8),
              Text('Fade: ${fade.toStringAsFixed(2)}s', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              Slider(value: fade, min: 0, max: 10, onChanged: (v) => setDialogState(() => fade = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == true) {
      setState(() {
        _steps[index] = ChaseStep(
          sceneId: step.sceneId,
          bankId: step.bankId,
          hold: Duration(milliseconds: (hold * 1000).round()),
          fade: Duration(milliseconds: (fade * 1000).round()),
        );
      });
    }
  }

  Chase get _currentChase => widget.existing.copyWith(
    name: _nameController.text.trim().isEmpty ? widget.existing.name : _nameController.text.trim(),
    steps: _steps,
    stepSeconds: _stepSeconds,
    beatSync: _beatSync,
    direction: _direction,
  );

  Future<void> _togglePreview() async {
    if (_player.isPlaying) {
      _player.stop();
      setState(() => _playingIndex = null);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    Stream<DateTime>? beatStream;
    if (_beatSync) {
      final beatService = ref.read(beatDetectorProvider);
      final started = await beatService.start();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${beatService.lastError ?? 'Microphone unavailable'} — falling back to timed steps')),
          );
        }
      } else {
        beatStream = beatService.beatEvents;
      }
    }
    _player.play(
      chase: _currentChase,
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
      beatStream: beatStream,
      onStep: (index) {
        if (mounted) setState(() => _playingIndex = index);
      },
    );
    setState(() {});
  }

  void _save() {
    _player.stop();
    ref.read(chasesProvider.notifier).upsert(_currentChase);
    Navigator.of(context).pop();
  }

  String _stepLabel(ChaseStep step) {
    if (step.sceneId != null) {
      final matches = ref.read(scenesProvider).where((s) => s.id == step.sceneId);
      return matches.isEmpty ? 'Missing scene' : 'Scene: ${matches.first.name}';
    }
    if (step.bankId != null) {
      final matches = ref.read(banksProvider).where((b) => b.id == step.bankId);
      return matches.isEmpty ? 'Missing bank' : 'Bank: ${matches.first.name}';
    }
    return 'Empty step';
  }

  /// Scene names in a bank's filled slots, in slot order — what a bank step
  /// actually expands into when the chase plays.
  List<String> _bankSceneNames(String bankId) {
    final bankMatches = ref.read(banksProvider).where((b) => b.id == bankId);
    if (bankMatches.isEmpty) return const [];
    final scenes = ref.read(scenesProvider);
    final names = <String>[];
    for (final sceneId in bankMatches.first.sceneSlots) {
      if (sceneId == null) continue;
      final sceneMatches = scenes.where((s) => s.id == sceneId);
      names.add(sceneMatches.isEmpty ? 'Missing scene' : sceneMatches.first.name);
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'STEPS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _addStep(asBank: false),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Scene'),
                  ),
                  TextButton.icon(
                    onPressed: () => _addStep(asBank: true),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Bank'),
                  ),
                ],
              ),
            ],
          ),
          Card(
            child: _steps.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No steps yet', style: TextStyle(color: AppColors.textFaint)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _steps.length; i++) ...[
                        ListTile(
                          onTap: _steps[i].bankId != null
                              ? () => setState(() {
                                  if (_expandedBankSteps.contains(i)) {
                                    _expandedBankSteps.remove(i);
                                  } else {
                                    _expandedBankSteps.add(i);
                                  }
                                })
                              : () => _editStepTiming(i),
                          leading: CircleAvatar(
                            radius: 13,
                            backgroundColor: i == _playingIndex ? AppColors.accent : AppColors.panel2,
                            foregroundColor: i == _playingIndex ? AppColors.accentOn : AppColors.accent2,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                          ),
                          title: Text(_stepLabel(_steps[i]), style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            _steps[i].bankId != null
                                ? 'Hold ${(_steps[i].hold.inMilliseconds / 1000).toStringAsFixed(2)}s · Fade ${(_steps[i].fade.inMilliseconds / 1000).toStringAsFixed(2)}s · tap to see scenes'
                                : 'Hold ${(_steps[i].hold.inMilliseconds / 1000).toStringAsFixed(2)}s · Fade ${(_steps[i].fade.inMilliseconds / 1000).toStringAsFixed(2)}s · tap to edit',
                            style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_steps[i].bankId != null)
                                IconButton(
                                  icon: const Icon(Icons.schedule, size: 16),
                                  tooltip: 'Edit timing',
                                  onPressed: () => _editStepTiming(i),
                                ),
                              IconButton(icon: const Icon(Icons.arrow_upward, size: 16), onPressed: () => _moveStep(i, -1)),
                              IconButton(icon: const Icon(Icons.arrow_downward, size: 16), onPressed: () => _moveStep(i, 1)),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => _removeStep(i)),
                            ],
                          ),
                        ),
                        if (_steps[i].bankId != null && _expandedBankSteps.contains(i))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(56, 0, 16, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final entry in _bankSceneNames(_steps[i].bankId!).asMap().entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      '${entry.key + 1}. ${entry.value}',
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                                    ),
                                  ),
                                if (_bankSceneNames(_steps[i].bankId!).isEmpty)
                                  const Text(
                                    'This bank has no scenes yet',
                                    style: TextStyle(fontSize: 11.5, color: AppColors.textFaint, fontStyle: FontStyle.italic),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          const Text(
            'SPEED & SYNC',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Applies to every step (and new ones) — override a single step by tapping it',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  const Text('Hold Time', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  Slider(
                    value: _stepSeconds,
                    min: 0.0,
                    max: 5,
                    onChanged: (v) => setState(() {
                      _stepSeconds = v;
                      _applyHoldToAllSteps();
                    }),
                    onChangeEnd: (_) => _restartIfPlaying(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${_stepSeconds.toStringAsFixed(2)}s / step', style: appMonoStyle(fontSize: 11)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fade Time (still applies even when synced to beat)',
                    style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
                  Slider(
                    value: _defaultFadeSeconds,
                    min: 0.0,
                    max: 5,
                    activeColor: AppColors.accent2,
                    onChanged: (v) => setState(() {
                      _defaultFadeSeconds = v;
                      _applyFadeToAllSteps();
                    }),
                    onChangeEnd: (_) => _restartIfPlaying(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${_defaultFadeSeconds.toStringAsFixed(2)}s fade', style: appMonoStyle(fontSize: 11)),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sync to Beat (Mic)', style: TextStyle(fontWeight: FontWeight.w600)),
                      Switch(
                        value: _beatSync,
                        onChanged: (v) {
                          setState(() => _beatSync = v);
                          _restartIfPlaying();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ChaseDirection>(
                    segments: const [
                      ButtonSegment(value: ChaseDirection.forward, label: Text('Forward')),
                      ButtonSegment(value: ChaseDirection.bounce, label: Text('Bounce')),
                      ButtonSegment(value: ChaseDirection.random, label: Text('Random')),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (s) => setState(() => _direction = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _steps.isEmpty ? null : _togglePreview,
                  icon: Icon(_player.isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_player.isPlaying ? 'Stop' : 'Preview'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _save, child: const Text('Save Chase'))),
            ],
          ),
        ],
      ),
    );
  }
}

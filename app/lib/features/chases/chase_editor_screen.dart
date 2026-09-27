import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/beat_detector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/beat_meter.dart';
import '../../core/widgets/layer_badge.dart';
import '../../models/chase.dart';
import '../../models/layer.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
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
  double _sensitivity = 0.6;
  BeatFrequencyBand _frequencyBand = BeatFrequencyBand.overall;

  /// The step index (into [_steps]) each lane is on while previewing.
  final Map<String, int> _playingStep = {};
  final Set<int> _expandedBankSteps = {};

  /// Layers added to this chase that have no steps yet — kept on screen so
  /// there's somewhere to add the first one.
  final Set<String> _emptyGroups = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing.name);
    _steps = [...widget.existing.steps];
    _stepSeconds = widget.existing.stepSeconds;
    _beatSync = widget.existing.beatSync;
    _direction = widget.existing.direction;
    _sensitivity = ref.read(beatDetectorProvider).sensitivity;
    _frequencyBand = ref.read(beatDetectorProvider).frequencyBand;
  }

  bool get _isThisPreviewing => layersPlaying(ref.read, widget.existing.id).isNotEmpty;

  @override
  void dispose() {
    // Playback persists across tabs, so something else may well be running
    // while this editor is open — only stop it if it's actually *our own*
    // preview, never something started elsewhere.
    if (_isThisPreviewing) stopEverywhere(ref.read, widget.existing.id);
    _nameController.dispose();
    super.dispose();
  }

  List<String> get _existingLayerIds => [for (final l in ref.read(layersProvider)) l.id];

  /// Indices into [_steps] of the steps on [layerId], in order.
  List<int> _stepsOn(String layerId) {
    final existing = _existingLayerIds;
    return [
      for (var i = 0; i < _steps.length; i++)
        if (laneOf(_steps[i], existing) == layerId) i,
    ];
  }

  /// Layer 1 as `null`, so a chase only records the steps meant elsewhere.
  static String? _storedLayerId(String layerId) => layerId == layer1Id ? null : layerId;

  Future<void> _addStep({required bool asBank, required String layerId}) async {
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
    final layer = _storedLayerId(layerId);
    setState(() {
      _steps.add(
        asBank
            ? ChaseStep(bankId: chosenId, hold: hold, fade: fade, layerId: layer)
            : ChaseStep(sceneId: chosenId, hold: hold, fade: fade, layerId: layer),
      );
      _emptyGroups.remove(layerId);
      _expandedBankSteps.clear();
    });
  }

  void _applyHoldToAllSteps() {
    final hold = Duration(milliseconds: (_stepSeconds * 1000).round());
    _steps = [for (final step in _steps) step.copyWith(hold: hold)];
  }

  void _applyFadeToAllSteps() {
    final fade = Duration(milliseconds: (_defaultFadeSeconds * 1000).round());
    _steps = [for (final step in _steps) step.copyWith(fade: fade)];
  }

  void _restartIfPlaying() {
    if (!_isThisPreviewing) return;
    stopEverywhere(ref.read, widget.existing.id);
    _togglePreview();
  }

  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
      _expandedBankSteps.clear();
    });
  }

  /// Swaps the step at [index] with its neighbour on the same layer.
  void _moveStep(int index, int delta) {
    final lane = _stepsOn(laneOf(_steps[index], _existingLayerIds));
    final position = lane.indexOf(index) + delta;
    if (position < 0 || position >= lane.length) return;
    final other = lane[position];
    setState(() {
      final step = _steps[index];
      _steps[index] = _steps[other];
      _steps[other] = step;
      _expandedBankSteps.clear();
    });
  }

  /// Moves the step at [index] to the end of [layerId]'s group.
  void _moveToLayer(int index, String layerId) {
    setState(() {
      final step = _steps.removeAt(index);
      _steps.add(layerId == layer1Id ? step.copyWith(clearLayer: true) : step.copyWith(layerId: layerId));
      _emptyGroups.remove(layerId);
      _expandedBankSteps.clear();
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
        _steps[index] = step.copyWith(
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

  /// How many instants (played looks) a step expands into — one for a
  /// scene, one per filled slot for a bank — so a lane's instant index can
  /// be traced back to the step it belongs to.
  int _instantCount(ChaseStep step) {
    final scenes = ref.read(scenesProvider);
    if (step.sceneId != null) return scenes.any((s) => s.id == step.sceneId) ? 1 : 0;
    final banks = ref.read(banksProvider).where((b) => b.id == step.bankId);
    if (banks.isEmpty) return 0;
    return banks.first.sceneSlots.where((id) => id != null && scenes.any((s) => s.id == id)).length;
  }

  int? _stepForInstant(String layerId, int instant) {
    var seen = 0;
    for (final index in _stepsOn(layerId)) {
      seen += _instantCount(_steps[index]);
      if (instant < seen) return index;
    }
    return null;
  }

  Future<void> _togglePreview() async {
    if (_isThisPreviewing) {
      stopEverywhere(ref.read, widget.existing.id);
      setState(_playingStep.clear);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    if (_beatSync) {
      final beatService = ref.read(activeBeatSourceProvider);
      if (!await beatService.start() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${beatService.lastError ?? 'Microphone unavailable'} — falling back to timed steps')),
        );
      }
    }
    final chase = _currentChase;
    final started = await startLayeredChase(
      ref.read,
      chase,
      playing: NowPlaying(id: widget.existing.id, kind: PlaybackKind.chase, name: chase.name),
      onStep: (layerId, instant) {
        if (!mounted) return;
        final index = _stepForInstant(layerId, instant);
        setState(() {
          if (index == null) {
            _playingStep.remove(layerId);
          } else {
            _playingStep[layerId] = index;
          }
        });
      },
    );
    // A step whose scene or bank doesn't exist flattens to nothing, and the
    // player quietly declines to run zero steps.
    if (started.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to preview — add a step with a valid scene or bank first')),
      );
    }
    if (mounted) setState(() {});
  }

  void _save() {
    if (_isThisPreviewing) stopEverywhere(ref.read, widget.existing.id);
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

  List<Widget> _layerGroups() {
    final layers = ref.watch(layersProvider);
    final existing = [for (final l in layers) l.id];
    final used = {for (final step in _steps) laneOf(step, existing)};
    final shown = [
      for (final layer in layers)
        if (layer.id == layer1Id || used.contains(layer.id) || _emptyGroups.contains(layer.id)) layer,
    ];
    final addable = [for (final layer in layers) if (!shown.contains(layer)) layer];
    return [
      for (final layer in shown) _layerGroup(layer, layers.indexOf(layer), layers),
      if (addable.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: 'Add a layer to this chase',
          color: AppColors.panel2,
          onSelected: (id) => setState(() => _emptyGroups.add(id)),
          itemBuilder: (context) => [
            for (final layer in addable)
              PopupMenuItem(
                value: layer.id,
                child: Row(
                  children: [
                    LayerBadge(index: layers.indexOf(layer)),
                    const SizedBox(width: 8),
                    Text(layer.name),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.add, size: 18, color: AppColors.textDim),
                SizedBox(width: 8),
                Text('Add a layer to this chase', style: TextStyle(fontSize: 12.5, color: AppColors.textDim, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _layerGroup(Layer layer, int layerIndex, List<Layer> layers) {
    final indices = _stepsOn(layer.id);
    final color = layerColor(layerIndex);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: const BoxDecoration(
              color: AppColors.panel2,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                LayerBadge(index: layerIndex),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(layer.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      Text(
                        '${indices.length} ${indices.length == 1 ? 'step' : 'steps'}'
                        '${layer.id == layer1Id ? ' · default layer' : ''}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                ),
                if (indices.isEmpty && layer.id != layer1Id)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Remove this empty layer from the chase',
                    onPressed: () => setState(() => _emptyGroups.remove(layer.id)),
                  ),
              ],
            ),
          ),
          if (indices.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('No steps on this layer yet', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
            ),
          for (var position = 0; position < indices.length; position++)
            ..._stepTile(indices[position], position, layer.id, layers),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _addStep(asBank: false, layerId: layer.id),
                  icon: Icon(Icons.add, size: 16, color: color),
                  label: Text('Scene', style: TextStyle(color: color)),
                ),
                TextButton.icon(
                  onPressed: () => _addStep(asBank: true, layerId: layer.id),
                  icon: Icon(Icons.add, size: 16, color: color),
                  label: Text('Bank', style: TextStyle(color: color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _stepTile(int i, int position, String layerId, List<Layer> layers) {
    final step = _steps[i];
    final playing = _playingStep[layerId] == i;
    final timing =
        'Hold ${(step.hold.inMilliseconds / 1000).toStringAsFixed(2)}s · Fade ${(step.fade.inMilliseconds / 1000).toStringAsFixed(2)}s';
    return [
      ListTile(
        onTap: step.bankId != null
            ? () => setState(() {
                if (!_expandedBankSteps.remove(i)) _expandedBankSteps.add(i);
              })
            : () => _editStepTiming(i),
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: playing ? AppColors.accent : AppColors.panel2,
          foregroundColor: playing ? AppColors.accentOn : AppColors.accent2,
          child: Text('${position + 1}', style: const TextStyle(fontSize: 11)),
        ),
        title: Text(_stepLabel(step), style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          step.bankId != null ? '$timing · tap to see scenes' : '$timing · tap to edit',
          style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (step.bankId != null)
              IconButton(
                icon: const Icon(Icons.schedule, size: 16),
                tooltip: 'Edit timing',
                onPressed: () => _editStepTiming(i),
              ),
            if (layers.length > 1)
              PopupMenuButton<String>(
                icon: const Icon(Icons.layers_outlined, size: 16),
                tooltip: 'Move to another layer',
                color: AppColors.panel2,
                onSelected: (id) => _moveToLayer(i, id),
                itemBuilder: (context) => [
                  for (var l = 0; l < layers.length; l++)
                    if (layers[l].id != layerId)
                      PopupMenuItem(
                        value: layers[l].id,
                        child: Row(
                          children: [
                            LayerBadge(index: l),
                            const SizedBox(width: 8),
                            Text('Move to ${layers[l].name}'),
                          ],
                        ),
                      ),
                ],
              ),
            IconButton(icon: const Icon(Icons.arrow_upward, size: 16), onPressed: () => _moveStep(i, -1)),
            IconButton(icon: const Icon(Icons.arrow_downward, size: 16), onPressed: () => _moveStep(i, 1)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 16), onPressed: () => _removeStep(i)),
          ],
        ),
      ),
      if (step.bankId != null && _expandedBankSteps.contains(i))
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in _bankSceneNames(step.bankId!).asMap().entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${entry.key + 1}. ${entry.value}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                  ),
                ),
              if (_bankSceneNames(step.bankId!).isEmpty)
                const Text(
                  'This bank has no scenes yet',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textFaint, fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
    ];
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
          const Text(
            'STEPS BY LAYER',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const Text(
            'Each layer is a lane: its steps play one after another, and the lanes play at the same time. '
            'New steps land on Layer 1 unless added to another layer.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          ..._layerGroups(),
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
                  Text(
                    _beatSync ? 'Hold Time (synced to beat)' : 'Hold Time',
                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
                  Slider(
                    value: _stepSeconds,
                    min: 0.0,
                    max: 5,
                    onChanged: _beatSync
                        ? null
                        : (v) => setState(() {
                            _stepSeconds = v;
                            _applyHoldToAllSteps();
                          }),
                    onChangeEnd: _beatSync ? null : (_) => _restartIfPlaying(),
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
                  if (_beatSync) ...[
                    const SizedBox(height: 10),
                    BeatMeter(service: ref.read(beatDetectorProvider)),
                    const SizedBox(height: 10),
                    const Text(
                      'Sensitivity',
                      style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                    Slider(
                      value: _sensitivity,
                      activeColor: AppColors.accent2,
                      onChanged: (v) {
                        setState(() => _sensitivity = v);
                        ref.read(beatDetectorProvider).sensitivity = v;
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'React to',
                      style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                    const SizedBox(height: 6),
                    // Six bands of labelled segments are wider than a phone
                    // — and a SegmentedButton overflows rather than shrinks
                    // — so let the row scroll.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<BeatFrequencyBand>(
                        segments: [
                          for (final band in BeatFrequencyBand.values)
                            ButtonSegment(value: band, label: Text(band.label)),
                        ],
                        selected: {_frequencyBand},
                        onSelectionChanged: (selection) {
                          setState(() => _frequencyBand = selection.first);
                          ref.read(beatDetectorProvider).frequencyBand = selection.first;
                        },
                      ),
                    ),
                  ],
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
                  icon: Icon(_isThisPreviewing ? Icons.stop : Icons.play_arrow),
                  label: Text(_isThisPreviewing ? 'Stop' : 'Preview'),
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

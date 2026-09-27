import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/smart_layer_display.dart';
import '../../core/remote/trigger_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/layer_badge.dart';
import '../../models/layer.dart';
import '../../models/smart_program.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/smart_program_providers.dart';

class SmartProgramEditorScreen extends ConsumerStatefulWidget {
  final SmartProgram existing;

  const SmartProgramEditorScreen({super.key, required this.existing});

  @override
  ConsumerState<SmartProgramEditorScreen> createState() => _SmartProgramEditorScreenState();
}

class _SmartProgramEditorScreenState extends ConsumerState<SmartProgramEditorScreen> {
  late final TextEditingController _nameController;

  /// Every layer's three zone targets, keyed by layer id — including layers
  /// with nothing set yet, so each one gets its row in every zone.
  late final Map<String, LayerZoneTargets> _targets;
  late double _baseBpm;
  late ThresholdMode _mode;
  late double _baseFadeSeconds;
  late double _fasterThreshold;
  late double _fasterHoldSeconds;
  late double _fasterFadeSeconds;
  late double _slowerThreshold;
  late double _slowerHoldSeconds;
  late double _slowerFadeSeconds;
  late double _blackoutFadeSeconds;

  // Each pick is held as a "chase:<id>" / "bank:<id>" / "lane:<chase>:<layer>"
  // key so one dropdown can offer every kind.
  static String? _keyFor(ProgramTarget? target) {
    if (target == null) return null;
    if (target.isBank) return 'bank:${target.id}';
    final lane = target.lane;
    return lane == null ? 'chase:${target.id}' : 'lane:${target.id}:$lane';
  }

  static ProgramTarget? _targetOf(String? key) {
    if (key == null) return null;
    if (key.startsWith('chase:')) return ProgramTarget(id: key.substring(6), isBank: false);
    if (key.startsWith('bank:')) return ProgramTarget(id: key.substring(5), isBank: true);
    if (key.startsWith('lane:')) {
      final parts = key.substring(5).split(':');
      if (parts.length == 2) return ProgramTarget(id: parts[0], isBank: false, lane: parts[1]);
    }
    return null;
  }

  /// Bumped to make the dropdowns forget a pick the user backed out of.
  int _pickerEpoch = 0;

  /// Picking a chase whose banks are split over several layers: offers to
  /// put each layer's banks on that same layer in this zone, instead of the
  /// whole chase on the one row it was picked on. Returns true when it
  /// handled the pick (split, or backed out); false to set it as usual.
  ///
  /// Only for chases made of banks — a bank is a self-contained look a
  /// layer can own, where a lone scene lifted out of its chase often isn't.
  Future<bool> _offerSplit(String chaseId, SmartProgramZone zone) async {
    final chase = ref.read(chasesProvider).where((c) => c.id == chaseId).firstOrNull;
    if (chase == null) return false;
    final layers = ref.read(layersProvider);
    final lanes = chaseLanes(chase, [for (final l in layers) l.id]);
    if (lanes.length < 2 || chase.steps.any((s) => s.bankId == null)) return false;
    final banks = ref.read(banksProvider);
    String bankName(String? id) => banks.where((b) => b.id == id).firstOrNull?.name ?? 'Missing bank';
    String layerLabel(String id) {
      final index = layers.indexWhere((l) => l.id == id);
      return 'L${index + 1} ${layers[index].name}';
    }

    final split = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text('„${chase.name}” több rétegen fut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in lanes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${layerLabel(entry.key)}: ${entry.value.steps.map((s) => bankName(s.bankId)).join(', ')}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Behúzzam a rétegeit a saját layereikre ebben a zónában (${_zoneName(zone)})?',
              style: const TextStyle(fontSize: 13, color: AppColors.textDim),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Mind ezen a rétegen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Szétosztás')),
        ],
      ),
    );
    if (!mounted) return true;
    if (split == null) {
      setState(() => _pickerEpoch++);
      return true;
    }
    if (!split) return false;
    setState(() {
      for (final entry in lanes.entries) {
        final steps = entry.value.steps;
        // One bank on the layer: pick the bank itself. Several: that
        // layer's share of the chase, playing them in order.
        final target = steps.length == 1
            ? ProgramTarget(id: steps.first.bankId!, isBank: true)
            : ProgramTarget(id: chase.id, isBank: false, lane: entry.key);
        _targets[entry.key] = _targets[entry.key]!.withZone(zone, target);
      }
      _pickerEpoch++;
    });
    return true;
  }

  static String _zoneName(SmartProgramZone zone) => switch (zone) {
    SmartProgramZone.base => 'Base',
    SmartProgramZone.faster => 'Faster',
    SmartProgramZone.slower => 'Slower',
  };

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameController = TextEditingController(text: p.name);
    _targets = {
      for (final layer in ref.read(layersProvider)) layer.id: p.targetsFor(layer.id),
    };
    _baseBpm = p.baseBpm;
    _mode = p.thresholdMode;
    _baseFadeSeconds = p.baseFade.inMilliseconds / 1000;
    _fasterThreshold = p.fasterThreshold;
    _fasterHoldSeconds = p.fasterHold.inMilliseconds / 1000;
    _fasterFadeSeconds = p.fasterFade.inMilliseconds / 1000;
    _slowerThreshold = p.slowerThreshold;
    _slowerHoldSeconds = p.slowerHold.inMilliseconds / 1000;
    _slowerFadeSeconds = p.slowerFade.inMilliseconds / 1000;
    _blackoutFadeSeconds = p.blackoutFade.inMilliseconds / 1000;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  SmartProgram get _current => widget.existing
      .copyWith(
        name: _nameController.text.trim().isEmpty ? widget.existing.name : _nameController.text.trim(),
        baseBpm: _baseBpm,
        thresholdMode: _mode,
        baseFade: Duration(milliseconds: (_baseFadeSeconds * 1000).round()),
        fasterThreshold: _fasterThreshold,
        fasterHold: Duration(milliseconds: (_fasterHoldSeconds * 1000).round()),
        fasterFade: Duration(milliseconds: (_fasterFadeSeconds * 1000).round()),
        slowerThreshold: _slowerThreshold,
        slowerHold: Duration(milliseconds: (_slowerHoldSeconds * 1000).round()),
        slowerFade: Duration(milliseconds: (_slowerFadeSeconds * 1000).round()),
        blackoutFade: Duration(milliseconds: (_blackoutFadeSeconds * 1000).round()),
      )
      .withLayerTargets(_targets.values.toList());

  void _save() {
    ref.read(smartProgramsProvider.notifier).upsert(_current);
    // If this program is the one currently playing, the edit lands on the
    // running show rather than waiting for a restart.
    syncRunningSmartProgram(ref.read);
    Navigator.of(context).pop();
  }

  String get _unit => _mode == ThresholdMode.percent ? '%' : 'BPM';

  bool get _anyFaster => _targets.values.any((t) => t.faster != null);
  bool get _anySlower => _targets.values.any((t) => t.slower != null);

  /// One layer's pick for one zone, offering every saved chase *and* every
  /// bank.
  Widget _layerPicker(Layer layer, int index, SmartProgramZone zone) {
    final chases = ref.watch(chasesProvider);
    final banks = ref.watch(banksProvider);
    final targets = _targets[layer.id]!;
    final value = _keyFor(targets.explicit(zone));
    final String emptyLabel;
    if (zone == SmartProgramZone.base) {
      emptyLabel = '— nincs —';
    } else if (targets.base != null) {
      emptyLabel = '— marad a Base —';
    } else {
      emptyLabel = '— nincs —';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 30, child: LayerBadge(index: index)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              // Keyed so a value set here elsewhere (none today, but cheap)
              // still redraws the field instead of keeping its first pick.
              key: ValueKey('${layer.id}-${zone.name}-$value-$_pickerEpoch'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: layer.name, isDense: true),
              items: [
                DropdownMenuItem(value: null, child: Text(emptyLabel, style: const TextStyle(color: AppColors.textFaint))),
                // A layer's share of a split chase — only listed while picked.
                if (value != null && value.startsWith('lane:'))
                  DropdownMenuItem(
                    value: value,
                    child: Text(
                      'Chase · ${targetName(_targetOf(value)!, chases: chases, banks: banks, layers: ref.watch(layersProvider))}',
                    ),
                  ),
                for (final chase in chases)
                  DropdownMenuItem(value: 'chase:${chase.id}', child: Text('Chase · ${chase.name}')),
                for (final bank in banks) DropdownMenuItem(value: 'bank:${bank.id}', child: Text('Bank · ${bank.name}')),
              ],
              onChanged: (v) async {
                final target = _targetOf(v);
                if (target != null && !target.isBank && target.lane == null && await _offerSplit(target.id, zone)) {
                  return;
                }
                if (!mounted) return;
                setState(() => _targets[layer.id] = _targets[layer.id]!.withZone(zone, target));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerPickers(SmartProgramZone zone) {
    final layers = ref.watch(layersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < layers.length; i++)
          if (_targets.containsKey(layers[i].id)) _layerPicker(layers[i], i, zone),
      ],
    );
  }

  Widget _fadeSlider(double value, ValueChanged<double> onChanged, {Color color = AppColors.accent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fade Time: ${value.toStringAsFixed(2)}s', style: appMonoStyle(fontSize: 12)),
        Slider(value: value, min: 0, max: 5, activeColor: color, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    // A layer added on the Layers tab while this editor is open still gets
    // its rows.
    for (final layer in ref.watch(layersProvider)) {
      _targets.putIfAbsent(layer.id, () => LayerZoneTargets(layerId: layer.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'How this works',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const Text(
            'One tempo reading switches the whole program between Base, Faster '
            'and Slower once the live tempo has stayed past a threshold for '
            'that direction\'s hold time — but each layer plays its own chase '
            'or bank in each zone. A layer with nothing set for a zone keeps '
            'its Base through it; a layer with no Base sits dark until one of '
            'its zones comes round. A chase picked here plays entirely on this '
            'layer, whatever layers its own steps name — unless it\'s made of '
            'banks spread over several layers: then you\'re asked whether to '
            'put each layer\'s banks on that layer instead.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 20),
          const Text('BASE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _layerPickers(SmartProgramZone.base),
                  const SizedBox(height: 6),
                  Text('Base BPM: ${_baseBpm.round()}', style: appMonoStyle(fontSize: 12)),
                  Slider(
                    value: _baseBpm,
                    min: 40,
                    max: 220,
                    divisions: 180,
                    onChanged: (v) => setState(() => _baseBpm = v),
                  ),
                  const SizedBox(height: 8),
                  _fadeSlider(_baseFadeSeconds, (v) => setState(() => _baseFadeSeconds = v)),
                  const SizedBox(height: 8),
                  const Text('Threshold Unit', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  const SizedBox(height: 6),
                  SegmentedButton<ThresholdMode>(
                    segments: const [
                      ButtonSegment(value: ThresholdMode.percent, label: Text('Percent')),
                      ButtonSegment(value: ThresholdMode.bpm, label: Text('BPM')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.speed, size: 14, color: AppColors.accent2),
              const SizedBox(width: 6),
              const Text('FASTER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
              const Spacer(),
              Text(
                'triggers at ${current.fasterTriggerBpm.toStringAsFixed(0)} BPM',
                style: appMonoStyle(fontSize: 10.5, color: AppColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _layerPickers(SmartProgramZone.faster),
                  if (_anyFaster) ...[
                    const SizedBox(height: 6),
                    Text('Speed up by: +${_fasterThreshold.toStringAsFixed(0)}$_unit', style: appMonoStyle(fontSize: 12)),
                    Slider(
                      value: _fasterThreshold,
                      min: 1,
                      max: _mode == ThresholdMode.percent ? 100 : 120,
                      activeColor: AppColors.accent2,
                      onChanged: (v) => setState(() => _fasterThreshold = v),
                    ),
                    Text(
                      'Hold for: ${_fasterHoldSeconds.toStringAsFixed(1)}s before switching',
                      style: appMonoStyle(fontSize: 12),
                    ),
                    Slider(
                      value: _fasterHoldSeconds,
                      min: 0,
                      max: 15,
                      activeColor: AppColors.accent2,
                      onChanged: (v) => setState(() => _fasterHoldSeconds = v),
                    ),
                    const SizedBox(height: 8),
                    _fadeSlider(
                      _fasterFadeSeconds,
                      (v) => setState(() => _fasterFadeSeconds = v),
                      color: AppColors.accent2,
                    ),
                  ] else
                    const Text(
                      'No layer has a Faster pick — the program stays on Base when the song speeds up.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.slow_motion_video, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              const Text('SLOWER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
              const Spacer(),
              Text(
                'triggers at ${current.slowerTriggerBpm.toStringAsFixed(0)} BPM',
                style: appMonoStyle(fontSize: 10.5, color: AppColors.textDim),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _layerPickers(SmartProgramZone.slower),
                  if (_anySlower) ...[
                    const SizedBox(height: 6),
                    Text('Slow down by: -${_slowerThreshold.toStringAsFixed(0)}$_unit', style: appMonoStyle(fontSize: 12)),
                    Slider(
                      value: _slowerThreshold,
                      min: 1,
                      max: _mode == ThresholdMode.percent ? 100 : 120,
                      onChanged: (v) => setState(() => _slowerThreshold = v),
                    ),
                    Text(
                      'Hold for: ${_slowerHoldSeconds.toStringAsFixed(1)}s before switching',
                      style: appMonoStyle(fontSize: 12),
                    ),
                    Slider(
                      value: _slowerHoldSeconds,
                      min: 0,
                      max: 15,
                      onChanged: (v) => setState(() => _slowerHoldSeconds = v),
                    ),
                    const SizedBox(height: 8),
                    _fadeSlider(_slowerFadeSeconds, (v) => setState(() => _slowerFadeSeconds = v)),
                  ] else
                    const Text(
                      'No layer has a Slower pick — the program stays on Base when the song slows down.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.nightlight_outlined, size: 14, color: AppColors.textFaint),
              SizedBox(width: 6),
              Text(
                'WHEN THE MUSIC STOPS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'After 4s without a beat the rig fades out and waits. The '
                    'first beat back brings the slower picks up again.',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Blackout Fade: ${_blackoutFadeSeconds.toStringAsFixed(1)}s',
                    style: appMonoStyle(fontSize: 12),
                  ),
                  Slider(
                    value: _blackoutFadeSeconds,
                    min: 0,
                    max: 15,
                    onChanged: (v) => setState(() => _blackoutFadeSeconds = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save Smart Program')),
        ],
      ),
    );
  }
}

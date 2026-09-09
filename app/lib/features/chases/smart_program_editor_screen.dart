import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/smart_program.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/smart_program_providers.dart';

class SmartProgramEditorScreen extends ConsumerStatefulWidget {
  final SmartProgram existing;

  const SmartProgramEditorScreen({super.key, required this.existing});

  @override
  ConsumerState<SmartProgramEditorScreen> createState() => _SmartProgramEditorScreenState();
}

class _SmartProgramEditorScreenState extends ConsumerState<SmartProgramEditorScreen> {
  late final TextEditingController _nameController;
  // Each zone's pick is held as a "chase:<id>" / "bank:<id>" key so one
  // dropdown can offer both kinds; it's split back into the model's two id
  // fields on save.
  late String? _baseKey;
  late double _baseBpm;
  late ThresholdMode _mode;
  late double _baseFadeSeconds;
  late String? _fasterKey;
  late double _fasterThreshold;
  late double _fasterHoldSeconds;
  late double _fasterFadeSeconds;
  late String? _slowerKey;
  late double _slowerThreshold;
  late double _slowerHoldSeconds;
  late double _slowerFadeSeconds;
  late double _blackoutFadeSeconds;

  static String? _keyFor(ProgramTarget? target) =>
      target == null ? null : '${target.isBank ? 'bank' : 'chase'}:${target.id}';
  static String? _chaseIdOf(String? key) => key != null && key.startsWith('chase:') ? key.substring(6) : null;
  static String? _bankIdOf(String? key) => key != null && key.startsWith('bank:') ? key.substring(5) : null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameController = TextEditingController(text: p.name);
    _baseKey = _keyFor(p.baseTarget);
    _baseBpm = p.baseBpm;
    _mode = p.thresholdMode;
    _baseFadeSeconds = p.baseFade.inMilliseconds / 1000;
    _fasterKey = _keyFor(p.fasterTarget);
    _fasterThreshold = p.fasterThreshold;
    _fasterHoldSeconds = p.fasterHold.inMilliseconds / 1000;
    _fasterFadeSeconds = p.fasterFade.inMilliseconds / 1000;
    _slowerKey = _keyFor(p.slowerTarget);
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

  SmartProgram get _current => widget.existing.copyWith(
    name: _nameController.text.trim().isEmpty ? widget.existing.name : _nameController.text.trim(),
    // The pickers are authoritative for every zone's target, so pass both
    // ids explicitly (clear* makes copyWith take them verbatim, nulls and
    // all) rather than merging with whatever was set before.
    baseChaseId: _chaseIdOf(_baseKey),
    baseBankId: _bankIdOf(_baseKey),
    clearBase: true,
    baseBpm: _baseBpm,
    thresholdMode: _mode,
    baseFade: Duration(milliseconds: (_baseFadeSeconds * 1000).round()),
    fasterChaseId: _chaseIdOf(_fasterKey),
    fasterBankId: _bankIdOf(_fasterKey),
    clearFaster: true,
    fasterThreshold: _fasterThreshold,
    fasterHold: Duration(milliseconds: (_fasterHoldSeconds * 1000).round()),
    fasterFade: Duration(milliseconds: (_fasterFadeSeconds * 1000).round()),
    slowerChaseId: _chaseIdOf(_slowerKey),
    slowerBankId: _bankIdOf(_slowerKey),
    clearSlower: true,
    slowerThreshold: _slowerThreshold,
    slowerHold: Duration(milliseconds: (_slowerHoldSeconds * 1000).round()),
    slowerFade: Duration(milliseconds: (_slowerFadeSeconds * 1000).round()),
    blackoutFade: Duration(milliseconds: (_blackoutFadeSeconds * 1000).round()),
  );

  void _save() {
    ref.read(smartProgramsProvider.notifier).upsert(_current);
    Navigator.of(context).pop();
  }

  String get _unit => _mode == ThresholdMode.percent ? '%' : 'BPM';

  /// One zone's target picker, offering every saved chase *and* every bank.
  Widget _targetPicker({
    required String label,
    required String emptyLabel,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final chases = ref.watch(chasesProvider);
    final banks = ref.watch(banksProvider);
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: null, child: Text(emptyLabel)),
        for (final chase in chases)
          DropdownMenuItem(value: 'chase:${chase.id}', child: Text('Chase · ${chase.name}')),
        for (final bank in banks) DropdownMenuItem(value: 'bank:${bank.id}', child: Text('Bank · ${bank.name}')),
      ],
      onChanged: onChanged,
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
            'The base chase plays at the song\'s normal tempo. When the live '
            'beat tempo drifts away from Base BPM by more than a threshold — '
            'and *stays* there for that direction\'s hold time — playback '
            'switches to the faster or slower chase, using that zone\'s own '
            'fade time. It switches back once the tempo returns to normal '
            'for the hold time again. The Dashboard\'s own Fade/Hold sliders '
            'disable themselves while this program runs.',
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
                  _targetPicker(
                    label: 'Base Program (normal tempo)',
                    emptyLabel: '— none —',
                    value: _baseKey,
                    onChanged: (v) => setState(() => _baseKey = v),
                  ),
                  const SizedBox(height: 14),
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
                  _targetPicker(
                    label: 'Faster Program',
                    emptyLabel: '— disabled —',
                    value: _fasterKey,
                    onChanged: (v) => setState(() => _fasterKey = v),
                  ),
                  if (_fasterKey != null) ...[
                    const SizedBox(height: 14),
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
                  ],
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
                  _targetPicker(
                    label: 'Slower Program',
                    emptyLabel: '— disabled —',
                    value: _slowerKey,
                    onChanged: (v) => setState(() => _slowerKey = v),
                  ),
                  if (_slowerKey != null) ...[
                    const SizedBox(height: 14),
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
                  ],
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
                    'first beat back brings the slower program up again.',
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

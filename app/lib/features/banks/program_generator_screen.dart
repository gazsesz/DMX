import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/generator/program_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/fixture_profile.dart';
import '../../models/patched_fixture.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';

const _uuid = Uuid();

class ProgramGeneratorScreen extends ConsumerStatefulWidget {
  const ProgramGeneratorScreen({super.key});

  @override
  ConsumerState<ProgramGeneratorScreen> createState() => _ProgramGeneratorScreenState();
}

class _ProgramGeneratorScreenState extends ConsumerState<ProgramGeneratorScreen> {
  late final List<MapEntry<String, List<int>>> _palette = colorPresets.entries.toList();
  final Set<int> _selectedColors = {0, 6, 10};
  GeneratorEffect _effect = GeneratorEffect.colorChase;
  FixturePattern _pattern = FixturePattern.all;
  String _applyTo = 'all';
  String? _destinationBankId;
  int _sceneCount = 6;
  bool _alsoCreateChase = true;
  double _size = 1.0;
  double _fan = 0.0;
  double _shift = 0.0;

  void _toggleColor(int index) {
    setState(() {
      if (_selectedColors.contains(index)) {
        _selectedColors.remove(index);
      } else if (_selectedColors.length < 4) {
        _selectedColors.add(index);
      }
    });
  }

  List<PatchedFixture> _targetFixtures() {
    final all = ref.read(patchedFixturesProvider);
    switch (_applyTo) {
      case 'rgb':
        return all.where((f) => f.profile.category == FixtureCategory.rgb).toList();
      case 'moving':
        return all.where((f) => f.profile.category == FixtureCategory.movingHead).toList();
      default:
        return all;
    }
  }

  void _generate() {
    final targets = _targetFixtures();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching patched fixtures — patch some first')),
      );
      return;
    }
    final colors = [for (final i in _selectedColors) _palette[i].value];
    final scenes = generateScenes(
      effect: _effect,
      colors: colors,
      fixtures: targets,
      count: _sceneCount,
      idGenerator: () => _uuid.v4(),
      namePrefix: _effect.label,
      pattern: _pattern,
      size: _size,
      fan: _fan,
      shift: _shift,
    );
    if (scenes.isEmpty) return;

    final sceneNotifier = ref.read(scenesProvider.notifier);
    for (final scene in scenes) {
      sceneNotifier.upsert(scene);
    }

    final banksNotifier = ref.read(banksProvider.notifier);
    final String bankId;
    if (_destinationBankId == null) {
      bankId = banksNotifier.addBank().id;
    } else {
      bankId = _destinationBankId!;
    }

    var bank = ref.read(banksProvider).firstWhere((b) => b.id == bankId);
    final emptySlots = bank.sceneSlots.where((s) => s == null).length;
    if (emptySlots < scenes.length) {
      banksNotifier.resize(bankId, bank.sceneSlots.length + (scenes.length - emptySlots));
      bank = ref.read(banksProvider).firstWhere((b) => b.id == bankId);
    }
    var cursor = 0;
    for (final scene in scenes) {
      while (cursor < bank.sceneSlots.length && bank.sceneSlots[cursor] != null) {
        cursor++;
      }
      banksNotifier.setSlot(bankId, cursor, scene.id);
      cursor++;
    }

    if (_alsoCreateChase) {
      final chase = ref.read(chasesProvider.notifier).create('${_effect.label} Chase');
      ref.read(chasesProvider.notifier).upsert(chase.copyWith(steps: [bankStepFor(_effect, bankId)]));
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated ${scenes.length} scenes into a bank${_alsoCreateChase ? ' + chase' : ''}')),
    );
  }

  Widget _shapeSlider({
    required String label,
    required String hint,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
          ],
        ),
        Text(hint, style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
        Slider(value: value, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Program')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'BASE COLORS (pick up to 4)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _palette.length; i++)
                    InkWell(
                      onTap: () => _toggleColor(i),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Color.fromARGB(255, _palette[i].value[0], _palette[i].value[1], _palette[i].value[2]),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedColors.contains(i) ? Colors.white : AppColors.border,
                            width: _selectedColors.contains(i) ? 2.5 : 1.5,
                          ),
                        ),
                        child: _selectedColors.contains(i)
                            ? const Icon(Icons.circle, size: 6, color: Colors.black45)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'COLOR FX',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final effect in GeneratorEffect.values.where((e) => !e.isMove))
                ChoiceChip(
                  label: Text(effect.label),
                  selected: _effect == effect,
                  onSelected: (_) => setState(() => _effect = effect),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'MOVE FX',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const Text(
            'Beam movement — needs moving heads to show its shape',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final effect in GeneratorEffect.values.where((e) => e.isMove))
                ChoiceChip(
                  label: Text(effect.label),
                  selected: _effect == effect,
                  onSelected: (_) => setState(() => _effect = effect),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _effect.isMove ? 'SHAPE' : 'SHAPE (Shift staggers the palette)',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                children: [
                  if (_effect.isMove) ...[
                    _shapeSlider(
                      label: 'Size',
                      hint: 'How far the beams travel from centre',
                      value: _size,
                      onChanged: (v) => setState(() => _size = v),
                    ),
                    _shapeSlider(
                      label: 'Fan',
                      hint: 'Spreads the rig outward, left to right',
                      value: _fan,
                      onChanged: (v) => setState(() => _fan = v),
                    ),
                  ],
                  _shapeSlider(
                    label: 'Shift',
                    hint: _effect.isMove
                        ? 'Delays each fixture so the move ripples across the rig'
                        : 'Staggers the palette across the fixtures',
                    value: _shift,
                    onChanged: (v) => setState(() => _shift = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'FIXTURE PATTERN',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const Text(
            'Which fixtures light up each scene — not always all of them at once',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pattern in FixturePattern.values)
                ChoiceChip(
                  label: Text(pattern.label),
                  selected: _pattern == pattern,
                  onSelected: (_) => setState(() => _pattern = pattern),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'APPLY TO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All Fixtures')),
              ButtonSegment(value: 'rgb', label: Text('RGB Only')),
              ButtonSegment(value: 'moving', label: Text('Moving Heads')),
            ],
            selected: {_applyTo},
            onSelectionChanged: (s) => setState(() => _applyTo = s.first),
          ),
          const SizedBox(height: 20),
          const Text(
            'OUTPUT',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Destination Bank'),
                    trailing: DropdownButton<String?>(
                      value: _destinationBankId,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('+ New Bank')),
                        for (final bank in banks) DropdownMenuItem(value: bank.id, child: Text(bank.name)),
                      ],
                      onChanged: (v) => setState(() => _destinationBankId = v),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Number of Scenes'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: _sceneCount > 1 ? () => setState(() => _sceneCount--) : null,
                        ),
                        SizedBox(width: 24, child: Text('$_sceneCount', textAlign: TextAlign.center)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          onPressed: _sceneCount < 32 ? () => setState(() => _sceneCount++) : null,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Also Create Chase'),
                    value: _alsoCreateChase,
                    onChanged: (v) => setState(() => _alsoCreateChase = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text('Generate $_sceneCount Scenes'),
          ),
        ],
      ),
    );
  }
}

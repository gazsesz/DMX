import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/generator/program_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_select.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/patched_fixture.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/stage_providers.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

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
  FixtureTypeFilter _typeFilter = FixtureTypeFilter.all;
  late Set<String> _selectedFixtures = fixtureIdsOf(ref.read(patchedFixturesProvider), _typeFilter);
  String? _destinationBankId;
  int _sceneCount = 6;
  // Off by default: what a generated program is for is the bank, and a
  // chase wrapping that one bank is something you ask for, not something
  // that should quietly pile up in the Chase list on every generate.
  bool _alsoCreateChase = false;
  double _shift = 0.0;
  int _strobeGroupSize = 1;
  StrobeDirection _strobeDirection = StrobeDirection.right;

  bool get _isRunningStrobe => _effect == GeneratorEffect.runningStrobe;

  /// What the Generate button will actually make — a running strobe sizes
  /// itself from the lamps picked.
  int get _plannedSceneCount => _isRunningStrobe
      ? runningStrobeSceneCount(_selectedFixtures.length, _strobeGroupSize, _strobeDirection)
      : _sceneCount;

  void _toggleColor(int index) {
    setState(() {
      if (_selectedColors.contains(index)) {
        _selectedColors.remove(index);
      } else if (_selectedColors.length < 4) {
        _selectedColors.add(index);
      }
    });
  }

  /// The picked lamps in the order the effect will walk them — the
  /// project's lamp order (saved with the stage plan).
  List<PatchedFixture> _targetFixtures() {
    final plan = ref.read(stagePlanProvider);
    return orderFixtures(
      [
        for (final f in ref.read(patchedFixturesProvider))
          if (_selectedFixtures.contains(f.id)) f,
      ],
      plan.fixtureOrder,
      customOrder: plan.customFixtureOrder,
    );
  }

  void _setOrder(FixtureOrder order) {
    final stage = ref.read(stagePlanProvider.notifier);
    // Switching to Custom starts from whatever order was showing, so the
    // stage order is one or two drags away instead of a full re-sort.
    if (order == FixtureOrder.custom && ref.read(stagePlanProvider).fixtureOrder != FixtureOrder.custom) {
      final shown = [for (final f in _targetFixtures()) f.id];
      final rest = ref.read(stagePlanProvider).customFixtureOrder.where((id) => !shown.contains(id));
      stage.setCustomFixtureOrder([...shown, ...rest]);
    }
    stage.setFixtureOrder(order);
  }

  void _reorder(List<PatchedFixture> shown, int oldIndex, int newIndex) {
    final ids = [for (final f in shown) f.id];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    // Lamps not ticked right now keep their place after the ones shown.
    final rest = ref.read(stagePlanProvider).customFixtureOrder.where((id) => !ids.contains(id));
    ref.read(stagePlanProvider.notifier).setCustomFixtureOrder([...ids, ...rest]);
  }

  Widget _orderSection() {
    final order = ref.watch(stagePlanProvider).fixtureOrder;
    ref.watch(patchedFixturesProvider);
    final shown = _targetFixtures();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.genFixtureOrder,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
        ),
        Text(
          context.l10n.genFixtureOrderHint,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in FixtureOrder.values)
              ChoiceChip(
                key: ValueKey('order-${o.name}'),
                label: Text(o.tr(context.l10n)),
                selected: order == o,
                onSelected: (_) => _setOrder(o),
              ),
          ],
        ),
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: order == FixtureOrder.custom
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.genFixtureOrderDragHint,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                        ),
                        ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorderItem: (a, b) => _reorder(shown, a, b),
                          children: [
                            for (var i = 0; i < shown.length; i++)
                              ListTile(
                                key: ValueKey('ordered-${shown[i].id}'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: _orderBadge(i),
                                title: Text(shown[i].label),
                                trailing: ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(Icons.drag_handle),
                                ),
                              ),
                          ],
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < shown.length; i++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _orderBadge(i),
                              const SizedBox(width: 4),
                              Text(shown[i].label, style: const TextStyle(fontSize: 12)),
                              if (i < shown.length - 1)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.chevron_right, size: 14, color: AppColors.textFaint),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _orderBadge(int index) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.border),
    ),
    child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
  );

  void _generate() {
    final targets = _targetFixtures();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.genNoFixtures)));
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
      shift: _shift,
      strobeGroupSize: _strobeGroupSize,
      strobeDirection: _strobeDirection,
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
    // Back on the Banks screen, the bank just generated into is the one
    // showing — not whichever happened to be selected before.
    ref.read(selectedBankIdProvider.notifier).state = bankId;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_alsoCreateChase ? context.l10n.genGeneratedWithChase(scenes.length) : context.l10n.genGenerated(scenes.length))),
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
      appBar: AppBar(title: Text(context.l10n.banksGenerateProgram)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            context.l10n.genBaseColors,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
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
          Text(
            context.l10n.genColorFx,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
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
          Text(
            context.l10n.genMovementMoved,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          const SizedBox(height: 20),
          if (_isRunningStrobe) ...[
            Text(
              context.l10n.genRunningStrobe,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
            Text(
              context.l10n.genRunningStrobeHint,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.genLampsAtOnce, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1')),
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                      ],
                      selected: {_strobeGroupSize},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _strobeGroupSize = s.first),
                    ),
                    const SizedBox(height: 12),
                    Text(context.l10n.genDirection, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SegmentedButton<StrobeDirection>(
                      segments: [for (final d in StrobeDirection.values) ButtonSegment(value: d, label: Text(d.tr(context.l10n)))],
                      selected: {_strobeDirection},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _strobeDirection = s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.genStrobeHint,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              context.l10n.genShape,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Column(
                  children: [
                    _shapeSlider(
                      label: 'Shift',
                      hint: _effect == GeneratorEffect.rainbowWave
                          ? context.l10n.genShiftWheelHint
                          : context.l10n.genShiftHint,
                      value: _shift,
                      onChanged: (v) => setState(() => _shift = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.genFixturePattern,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
            Text(
              context.l10n.genFixturePatternHint,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pattern in FixturePattern.values)
                  ChoiceChip(
                    label: Text(pattern.tr(context.l10n)),
                    selected: _pattern == pattern,
                    onSelected: (_) => setState(() => _pattern = pattern),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            context.l10n.genApplyTo,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FixtureChecklist(
                fixtures: ref.watch(patchedFixturesProvider),
                selected: _selectedFixtures,
                filter: _typeFilter,
                onChanged: (s) => setState(() => _selectedFixtures = s),
                // Picking a type ticks every fixture of it, to trim by hand.
                onFilterChanged: (f) => setState(() {
                  _typeFilter = f;
                  _selectedFixtures = fixtureIdsOf(ref.read(patchedFixturesProvider), f);
                }),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _orderSection(),
          const SizedBox(height: 20),
          Text(
            context.l10n.genOutput,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.genDestinationBank),
                    trailing: DropdownButton<String?>(
                      value: _destinationBankId,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(value: null, child: Text(context.l10n.genNewBank)),
                        for (final bank in banks) DropdownMenuItem(value: bank.id, child: Text(bank.name)),
                      ],
                      onChanged: (v) => setState(() => _destinationBankId = v),
                    ),
                  ),
                  if (!_isRunningStrobe) ...[
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.genNumberOfScenes),
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
                  ],
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.genAlsoCreateChase),
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
            label: Text(context.l10n.genGenerateButton(_plannedSceneCount)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/channel_slider.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/channel_function.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/universe_config.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';

/// A set of fixtures within a scene that share one set of channel values —
/// lets a scene mix looks, e.g. three fixtures purple and a fourth dark.
class _Group {
  final String id;
  final Set<String> fixtureIds;
  final Map<String, int> values;

  _Group({required this.id, required this.fixtureIds, required this.values});
}

const _newGroupSentinel = '__new_group__';

class SceneEditorScreen extends ConsumerStatefulWidget {
  final Scene? existing;

  const SceneEditorScreen({super.key, this.existing});

  @override
  ConsumerState<SceneEditorScreen> createState() => _SceneEditorScreenState();
}

class _SceneEditorScreenState extends ConsumerState<SceneEditorScreen> {
  late final TextEditingController _nameController;
  final List<_Group> _groups = [];
  int _groupCounter = 0;

  /// Per-fixture values remembered across un-check/re-check within this
  /// editing session (and seeded from the saved scene on open), so toggling
  /// a fixture off and back on restores its look instead of zeroing it.
  final Map<String, Map<String, int>> _lastKnownValues = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? 'New Scene');
    final scene = widget.existing;
    if (scene != null) {
      final allFixtures = ref.read(patchedFixturesProvider);
      final perFixtureValues = <String, Map<String, int>>{};
      for (final entry in scene.fixtureValues.entries) {
        final fixture = allFixtures.where((f) => f.id == entry.key).firstOrNull;
        if (fixture == null) continue;
        final map = <String, int>{};
        final channels = fixture.profile.channels;
        for (var i = 0; i < channels.length && i < entry.value.length; i++) {
          map[channels[i].function.name] = entry.value[i];
        }
        perFixtureValues[fixture.id] = map;
        _lastKnownValues[fixture.id] = map;
      }
      // Cluster fixtures that share an identical value map into one group,
      // so a previously-saved "3 purple, 1 dark" scene re-opens that way.
      final byValues = <String, _Group>{};
      for (final fixtureId in perFixtureValues.keys) {
        final map = perFixtureValues[fixtureId]!;
        final key = (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}:${e.value}')
            .join(',');
        final group = byValues.putIfAbsent(
          key,
          () => _Group(id: 'g${_groupCounter++}', fixtureIds: {}, values: Map.of(map)),
        );
        group.fixtureIds.add(fixtureId);
      }
      _groups.addAll(byValues.values);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<PatchedFixture> get _allFixtures => ref.read(patchedFixturesProvider);

  Set<String> get _selectedFixtureIds => {for (final g in _groups) ...g.fixtureIds};

  _Group? _groupOf(String fixtureId) {
    for (final g in _groups) {
      if (g.fixtureIds.contains(fixtureId)) return g;
    }
    return null;
  }

  List<PatchedFixture> _fixturesIn(_Group group) {
    final all = _allFixtures;
    return all.where((f) => group.fixtureIds.contains(f.id)).toList();
  }

  List<ChannelFunction> _sharedFunctionsFor(_Group group) {
    final functions = <ChannelFunction>{};
    for (final fixture in _fixturesIn(group)) {
      for (final channel in fixture.profile.channels) {
        functions.add(channel.function);
      }
    }
    final ordered = functions.toList()..sort((a, b) => a.index.compareTo(b.index));
    return ordered;
  }

  void _addFixtureToScene(PatchedFixture fixture) {
    setState(() {
      final cached = _lastKnownValues[fixture.id];
      _groups.add(
        _Group(id: 'g${_groupCounter++}', fixtureIds: {fixture.id}, values: cached != null ? Map.of(cached) : {}),
      );
    });
  }

  void _removeFixtureFromScene(PatchedFixture fixture) {
    setState(() {
      final group = _groupOf(fixture.id);
      if (group == null) return;
      _lastKnownValues[fixture.id] = Map.of(group.values);
      group.fixtureIds.remove(fixture.id);
      if (group.fixtureIds.isEmpty) _groups.remove(group);
    });
  }

  void _reassignFixture(PatchedFixture fixture, String targetGroupId) {
    setState(() {
      final current = _groupOf(fixture.id);
      if (current != null) {
        current.fixtureIds.remove(fixture.id);
        if (current.fixtureIds.isEmpty) _groups.remove(current);
      }
      if (targetGroupId == _newGroupSentinel) {
        final cached = _lastKnownValues[fixture.id];
        _groups.add(
          _Group(id: 'g${_groupCounter++}', fixtureIds: {fixture.id}, values: cached != null ? Map.of(cached) : {}),
        );
      } else {
        final target = _groups.where((g) => g.id == targetGroupId).firstOrNull;
        target?.fixtureIds.add(fixture.id);
      }
    });
  }

  int _valueForInGroup(_Group group, ChannelFunction function) => group.values[function.name] ?? 0;

  void _setValueInGroup(_Group group, ChannelFunction function, int value) {
    setState(() => group.values[function.name] = value.clamp(0, 255));
    for (final id in group.fixtureIds) {
      _lastKnownValues[id] = Map.of(group.values);
    }
    _pushLiveOutput();
  }

  void _applyColorToGroup(_Group group, List<int> rgb) {
    setState(() {
      group.values[ChannelFunction.red.name] = rgb[0];
      group.values[ChannelFunction.green.name] = rgb[1];
      group.values[ChannelFunction.blue.name] = rgb[2];
      final hasDimmer = _sharedFunctionsFor(group).contains(ChannelFunction.dimmer);
      if (hasDimmer && (group.values[ChannelFunction.dimmer.name] ?? 0) == 0) {
        group.values[ChannelFunction.dimmer.name] = 255;
      }
      for (final id in group.fixtureIds) {
        _lastKnownValues[id] = Map.of(group.values);
      }
    });
    _pushLiveOutput();
  }

  void _pushLiveOutput() {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    final universes = ref.read(universesProvider);
    final touched = <UniverseConfig>{};
    for (final group in _groups) {
      for (final fixture in _fixturesIn(group)) {
        final universeMatches = universes.where((u) => u.id == fixture.universeId);
        if (universeMatches.isEmpty) continue;
        final universe = universeMatches.first;
        touched.add(universe);
        for (final channel in fixture.profile.channels) {
          final value = group.values[channel.function.name];
          if (value == null) continue;
          service.setChannel(universe, fixture.startChannel + channel.offset, value, send: false);
        }
      }
    }
    for (final universe in touched) {
      service.flush(universe);
    }
  }

  Map<String, List<int>> _buildFixtureValues() {
    final result = <String, List<int>>{};
    for (final group in _groups) {
      for (final fixture in _fixturesIn(group)) {
        result[fixture.id] = [
          for (final channel in fixture.profile.channels) group.values[channel.function.name] ?? 0,
        ];
      }
    }
    return result;
  }

  /// A short human label for a group's look, e.g. "Purple", "Dark", "Moving".
  String _describeGroup(_Group group) {
    final functions = _sharedFunctionsFor(group);
    final hasDimmer = functions.contains(ChannelFunction.dimmer);
    if (hasDimmer && _valueForInGroup(group, ChannelFunction.dimmer) == 0) return 'Dark';
    final hasColor = functions.any((f) => f.isColorMix);
    if (hasColor) {
      final r = _valueForInGroup(group, ChannelFunction.red);
      final g = _valueForInGroup(group, ChannelFunction.green);
      final b = _valueForInGroup(group, ChannelFunction.blue);
      if (r < 8 && g < 8 && b < 8) return 'Dark';
      String? best;
      var bestDist = double.infinity;
      for (final entry in colorPresets.entries) {
        if (entry.key == 'Black') continue;
        final dr = r - entry.value[0];
        final dg = g - entry.value[1];
        final db = b - entry.value[2];
        final dist = (dr * dr + dg * dg + db * db).toDouble();
        if (dist < bestDist) {
          bestDist = dist;
          best = entry.key;
        }
      }
      return best ?? 'Custom';
    }
    if (functions.any((f) => f.isGobo)) {
      final idx = (_valueForInGroup(group, ChannelFunction.gobo) ~/ 32).clamp(0, goboPresets.length - 1);
      return 'Gobo: ${goboPresets[idx]}';
    }
    if (functions.any((f) => f.isPanTilt)) return 'Moving';
    return 'Custom';
  }

  String get _summaryLine {
    if (_groups.isEmpty) return '';
    final counts = <String, int>{};
    for (final group in _groups) {
      final label = _describeGroup(group).toLowerCase();
      counts[label] = (counts[label] ?? 0) + group.fixtureIds.length;
    }
    return counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
  }

  void _save() {
    if (_selectedFixtureIds.isEmpty || _nameController.text.trim().isEmpty) return;
    final fixtureValues = _buildFixtureValues();
    final notifier = ref.read(scenesProvider.notifier);
    if (widget.existing != null) {
      notifier.upsert(widget.existing!.copyWith(name: _nameController.text.trim(), fixtureValues: fixtureValues));
    } else {
      notifier.create(_nameController.text.trim(), fixtureValues);
    }
    Navigator.of(context).pop();
  }

  Future<void> _assignToBank() async {
    if (widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the scene first')),
      );
      return;
    }
    final banks = ref.read(banksProvider);
    if (banks.isEmpty) return;
    final selectedBank = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Assign to Bank'),
        children: [
          for (final bank in banks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, bank.id),
              child: Text(bank.name),
            ),
        ],
      ),
    );
    if (selectedBank == null || !mounted) return;
    final bank = banks.firstWhere((b) => b.id == selectedBank);
    final emptyIndex = bank.sceneSlots.indexWhere((slot) => slot == null);
    if (emptyIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That bank is full')));
      }
      return;
    }
    ref.read(banksProvider.notifier).setSlot(bank.id, emptyIndex, widget.existing!.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${bank.name}, slot ${emptyIndex + 1}')),
      );
    }
  }

  Widget _buildGroupCard(_Group group, int index) {
    final functions = _sharedFunctionsFor(group);
    final hasColor = functions.any((f) => f.isColorMix);
    final hasPanTilt = functions.any((f) => f.isPanTilt);
    final hasGobo = functions.any((f) => f.isGobo);
    final fixtures = _fixturesIn(group);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Group ${index + 1} · ${_describeGroup(group)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final fixture in fixtures)
                  InputChip(
                    label: Text(fixture.label, style: const TextStyle(fontSize: 11)),
                    onDeleted: () => _reassignFixture(fixture, _newGroupSentinel),
                    deleteIconColor: AppColors.textFaint,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasColor)
                  SizedBox(
                    width: 216,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in colorPresets.entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _applyColorToGroup(group, entry.value),
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Color.fromARGB(255, entry.value[0], entry.value[1], entry.value[2]),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hasColor) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasPanTilt)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (functions.contains(ChannelFunction.pan))
                              ChannelSliderTile(
                                label: 'Pan',
                                value: _valueForInGroup(group, ChannelFunction.pan),
                                color: AppColors.accent2,
                                onChanged: (v) => _setValueInGroup(group, ChannelFunction.pan, v),
                              ),
                            if (functions.contains(ChannelFunction.tilt))
                              ChannelSliderTile(
                                label: 'Tilt',
                                value: _valueForInGroup(group, ChannelFunction.tilt),
                                color: AppColors.accent2,
                                onChanged: (v) => _setValueInGroup(group, ChannelFunction.tilt, v),
                              ),
                          ],
                        ),
                      if (hasGobo) ...[
                        if (hasPanTilt) const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < goboPresets.length; i++)
                              ChoiceChip(
                                label: Text(goboPresets[i], style: const TextStyle(fontSize: 11)),
                                selected: _valueForInGroup(group, ChannelFunction.gobo) ~/ 32 == i,
                                onSelected: (_) => _setValueInGroup(group, ChannelFunction.gobo, i * 32),
                              ),
                          ],
                        ),
                        if (functions.contains(ChannelFunction.goboRotation))
                          ChannelSliderTile(
                            label: 'Rotation',
                            value: _valueForInGroup(group, ChannelFunction.goboRotation),
                            color: AppColors.accent2,
                            onChanged: (v) => _setValueInGroup(group, ChannelFunction.goboRotation, v),
                          ),
                      ],
                      if (functions.isNotEmpty) ...[
                        if (hasPanTilt || hasGobo) const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 10,
                          children: [
                            for (final function in functions)
                              ChannelSliderTile(
                                label: function.label,
                                value: _valueForInGroup(group, function),
                                color: AppColors.accent,
                                onChanged: (v) => _setValueInGroup(group, function, v),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allFixtures = ref.watch(patchedFixturesProvider);
    final selected = _selectedFixtureIds;

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
      body: allFixtures.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No patched fixtures yet.\nGo to the Fixtures tab, pick a template (built-in or your own),\nand tap "+ Patch" to assign it a universe + channel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_summaryLine.isNotEmpty) ...[
                  Text(
                    _summaryLine,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
                  ),
                  const SizedBox(height: 10),
                ],
                const Text(
                  'FIXTURES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                ),
                const Text(
                  'Pick which fixtures are part of this scene. Fixtures start in their own group — merge them below to share a look.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final fixture in allFixtures)
                      FilterChip(
                        label: Text(fixture.label),
                        selected: selected.contains(fixture.id),
                        onSelected: (isSelected) {
                          if (isSelected) {
                            _addFixtureToScene(fixture);
                          } else {
                            _removeFixtureFromScene(fixture);
                          }
                        },
                      ),
                  ],
                ),
                if (selected.isEmpty) ...[
                  const SizedBox(height: 40),
                  const Center(
                    child: Text('Select at least one fixture', style: TextStyle(color: AppColors.textFaint)),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  const Text(
                    'GROUPS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 4),
                  if (_groups.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final fixture in allFixtures.where((f) => selected.contains(f.id)))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${fixture.label}: ', style: const TextStyle(fontSize: 11)),
                                DropdownButton<String>(
                                  value: _groupOf(fixture.id)?.id,
                                  underline: const SizedBox.shrink(),
                                  style: const TextStyle(fontSize: 11, color: AppColors.text),
                                  dropdownColor: AppColors.panel2,
                                  items: [
                                    for (var i = 0; i < _groups.length; i++)
                                      DropdownMenuItem(value: _groups[i].id, child: Text('Group ${i + 1}')),
                                    const DropdownMenuItem(value: _newGroupSentinel, child: Text('+ New Group')),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    _reassignFixture(fixture, value);
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < _groups.length; i++) _buildGroupCard(_groups[i], i),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(onPressed: _assignToBank, child: const Text('Assign to Bank')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(onPressed: _save, child: const Text('Save Scene')),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

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

class SceneEditorScreen extends ConsumerStatefulWidget {
  final Scene? existing;

  const SceneEditorScreen({super.key, this.existing});

  @override
  ConsumerState<SceneEditorScreen> createState() => _SceneEditorScreenState();
}

class _SceneEditorScreenState extends ConsumerState<SceneEditorScreen> {
  late final TextEditingController _nameController;
  final Set<String> _selectedFixtureIds = {};

  /// channelKey -> value, where channelKey identifies a *function slot*
  /// shared across the selected fixtures (e.g. all their Dimmer channels
  /// move together), not one physical channel.
  final Map<String, int> _values = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? 'New Scene');
    if (widget.existing != null) {
      _selectedFixtureIds.addAll(widget.existing!.fixtureValues.keys);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<PatchedFixture> get _selectedFixtures {
    final all = ref.read(patchedFixturesProvider);
    return all.where((f) => _selectedFixtureIds.contains(f.id)).toList();
  }

  /// The set of distinct channel functions present across every selected
  /// fixture (deduplicated), used to build the shared control surface.
  List<ChannelFunction> get _sharedFunctions {
    final functions = <ChannelFunction>{};
    for (final fixture in _selectedFixtures) {
      for (final channel in fixture.profile.channels) {
        functions.add(channel.function);
      }
    }
    final ordered = functions.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return ordered;
  }

  int _valueFor(ChannelFunction function) {
    if (_values.containsKey(function.name)) return _values[function.name]!;
    // Seed from an existing scene's first matching fixture, else 0.
    final scene = widget.existing;
    if (scene != null) {
      for (final fixture in _selectedFixtures) {
        final stored = scene.fixtureValues[fixture.id];
        if (stored == null) continue;
        final idx = fixture.profile.channels.indexWhere((c) => c.function == function);
        if (idx != -1 && idx < stored.length) return stored[idx];
      }
    }
    return 0;
  }

  void _setValue(ChannelFunction function, int value) {
    setState(() => _values[function.name] = value.clamp(0, 255));
    _pushLiveOutput();
  }

  void _pushLiveOutput() {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    final universes = ref.read(universesProvider);
    final touched = <UniverseConfig>{};
    for (final fixture in _selectedFixtures) {
      final universeMatches = universes.where((u) => u.id == fixture.universeId);
      if (universeMatches.isEmpty) continue;
      final universe = universeMatches.first;
      touched.add(universe);
      for (final channel in fixture.profile.channels) {
        final value = _values[channel.function.name];
        if (value == null) continue;
        // send: false — one packet per universe below, not one per channel.
        service.setChannel(universe, fixture.startChannel + channel.offset, value, send: false);
      }
    }
    for (final universe in touched) {
      service.flush(universe);
    }
  }

  void _applyColor(List<int> rgb) {
    setState(() {
      _values[ChannelFunction.red.name] = rgb[0];
      _values[ChannelFunction.green.name] = rgb[1];
      _values[ChannelFunction.blue.name] = rgb[2];
      final hasDimmer = _sharedFunctions.contains(ChannelFunction.dimmer);
      if (hasDimmer && (_values[ChannelFunction.dimmer.name] ?? 0) == 0) {
        _values[ChannelFunction.dimmer.name] = 255;
      }
    });
    _pushLiveOutput();
  }

  Map<String, List<int>> _buildFixtureValues() {
    final result = <String, List<int>>{};
    for (final fixture in _selectedFixtures) {
      result[fixture.id] = [
        for (final channel in fixture.profile.channels) _values[channel.function.name] ?? 0,
      ];
    }
    return result;
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

  @override
  Widget build(BuildContext context) {
    final allFixtures = ref.watch(patchedFixturesProvider);
    final functions = _sharedFunctions;
    final hasColor = functions.any((f) => f.isColorMix);
    final hasPanTilt = functions.any((f) => f.isPanTilt);
    final hasGobo = functions.any((f) => f.isGobo);

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
                const Text(
                  'FIXTURES',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                ),
                const Text(
                  'Only patched fixtures show up here — create a fixture in the Fixtures tab, then tap "+ Patch" on it.',
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
                        selected: _selectedFixtureIds.contains(fixture.id),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedFixtureIds.add(fixture.id);
                            } else {
                              _selectedFixtureIds.remove(fixture.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
                if (_selectedFixtureIds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_selectedFixtureIds.length} fixtures selected — edits below apply to all',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                  ),
                if (functions.isEmpty) ...[
                  const SizedBox(height: 40),
                  const Center(
                    child: Text('Select at least one fixture', style: TextStyle(color: AppColors.textFaint)),
                  ),
                ],
                if (hasColor) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'COLOR',
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
                          for (final entry in colorPresets.entries)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _applyColor(entry.value),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Color.fromARGB(255, entry.value[0], entry.value[1], entry.value[2]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (hasPanTilt) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'PAN / TILT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          if (functions.contains(ChannelFunction.pan))
                            ChannelSliderTile(
                              label: 'Pan',
                              value: _valueFor(ChannelFunction.pan),
                              color: AppColors.accent2,
                              onChanged: (v) => _setValue(ChannelFunction.pan, v),
                            ),
                          if (functions.contains(ChannelFunction.tilt))
                            ChannelSliderTile(
                              label: 'Tilt',
                              value: _valueFor(ChannelFunction.tilt),
                              color: AppColors.accent2,
                              onChanged: (v) => _setValue(ChannelFunction.tilt, v),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (hasGobo) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'GOBO',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < goboPresets.length; i++)
                                ChoiceChip(
                                  label: Text(goboPresets[i]),
                                  selected: _valueFor(ChannelFunction.gobo) ~/ 32 == i,
                                  onSelected: (_) => _setValue(ChannelFunction.gobo, i * 32),
                                ),
                            ],
                          ),
                          if (functions.contains(ChannelFunction.goboRotation)) ...[
                            const SizedBox(height: 10),
                            ChannelSliderTile(
                              label: 'Rotation',
                              value: _valueFor(ChannelFunction.goboRotation),
                              color: AppColors.accent2,
                              onChanged: (v) => _setValue(ChannelFunction.goboRotation, v),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (functions.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'CHANNELS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Column(
                        children: [
                          for (final function in functions)
                            ChannelSliderTile(
                              label: function.label,
                              value: _valueFor(function),
                              color: AppColors.accent,
                              onChanged: (v) => _setValue(function, v),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
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

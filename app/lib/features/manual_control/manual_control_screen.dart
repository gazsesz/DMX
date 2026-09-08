import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/channel_slider.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/channel_function.dart';
import '../../models/patched_fixture.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';

/// A live "desk" view: every patched fixture with direct sliders, bypassing
/// scenes entirely. Values shown are seeded from whatever is already
/// playing on the node, so opening this screen never looks like a reset.
class ManualControlScreen extends ConsumerStatefulWidget {
  const ManualControlScreen({super.key});

  @override
  ConsumerState<ManualControlScreen> createState() => _ManualControlScreenState();
}

class _ManualControlScreenState extends ConsumerState<ManualControlScreen> {
  final Map<String, List<int>> _values = {};
  final Set<String> _expanded = {};
  String? _universeFilter;

  List<int> _valuesFor(PatchedFixture fixture) {
    return _values.putIfAbsent(fixture.id, () {
      final service = ref.read(artNetServiceProvider);
      final universeMatches = ref.read(universesProvider).where((u) => u.id == fixture.universeId);
      if (universeMatches.isEmpty) {
        return List<int>.filled(fixture.profile.channelCount, 0);
      }
      final universe = universeMatches.first;
      return [
        for (var i = 0; i < fixture.profile.channelCount; i++)
          service.getChannelValue(universe, fixture.startChannel + i),
      ];
    });
  }

  int? _valueForFunction(PatchedFixture fixture, ChannelFunction function) {
    final idx = fixture.profile.channels.indexWhere((c) => c.function == function);
    if (idx == -1) return null;
    return _valuesFor(fixture)[idx];
  }

  void _setChannel(PatchedFixture fixture, int offset, int value) {
    final values = _valuesFor(fixture);
    values[offset] = value.clamp(0, 255);
    final universeMatches = ref.read(universesProvider).where((u) => u.id == fixture.universeId);
    if (universeMatches.isNotEmpty) {
      final service = ref.read(artNetServiceProvider);
      if (service.isConnected) {
        service.setChannel(universeMatches.first, fixture.startChannel + offset, values[offset]);
      }
    }
    setState(() {});
  }

  void _togglePower(PatchedFixture fixture) {
    final dimmerIdx = fixture.profile.channels.indexWhere((c) => c.function == ChannelFunction.dimmer);
    if (dimmerIdx == -1) return;
    final current = _valuesFor(fixture)[dimmerIdx];
    _setChannel(fixture, dimmerIdx, current > 0 ? 0 : 255);
  }

  void _applyColor(PatchedFixture fixture, List<int> rgb) {
    final values = _valuesFor(fixture);
    final channels = fixture.profile.channels;
    final universeMatches = ref.read(universesProvider).where((u) => u.id == fixture.universeId);
    final service = ref.read(artNetServiceProvider);
    final canSend = universeMatches.isNotEmpty && service.isConnected;
    final universe = canSend ? universeMatches.first : null;

    void set(int index, int value) {
      values[index] = value;
      if (canSend) service.setChannel(universe!, fixture.startChannel + index, value, send: false);
    }

    for (var i = 0; i < channels.length; i++) {
      switch (channels[i].function) {
        case ChannelFunction.red:
          set(i, rgb[0]);
          break;
        case ChannelFunction.green:
          set(i, rgb[1]);
          break;
        case ChannelFunction.blue:
          set(i, rgb[2]);
          break;
        default:
          break;
      }
    }
    final dimmerIdx = channels.indexWhere((c) => c.function == ChannelFunction.dimmer);
    if (dimmerIdx != -1 && values[dimmerIdx] == 0) {
      set(dimmerIdx, 255);
    }
    if (canSend) service.flush(universe!);
    setState(() {});
  }

  void _blackout() {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    final universes = ref.read(universesProvider);
    service.blackoutAll(universes);
    for (final fixture in ref.read(patchedFixturesProvider)) {
      _values[fixture.id] = List<int>.filled(fixture.profile.channelCount, 0);
    }
    setState(() {});
  }

  Color _colorForFunction(ChannelFunction function) {
    switch (function) {
      case ChannelFunction.red:
        return const Color(0xFFEF4444);
      case ChannelFunction.green:
        return const Color(0xFF22C55E);
      case ChannelFunction.blue:
        return const Color(0xFF3B82F6);
      case ChannelFunction.pan:
      case ChannelFunction.panFine:
      case ChannelFunction.tilt:
      case ChannelFunction.tiltFine:
      case ChannelFunction.gobo:
      case ChannelFunction.goboRotation:
        return AppColors.accent2;
      default:
        return AppColors.accent;
    }
  }

  Widget _buildFixtureCard(PatchedFixture fixture) {
    final values = _valuesFor(fixture);
    final channels = fixture.profile.channels;
    final dimmerIdx = channels.indexWhere((c) => c.function == ChannelFunction.dimmer);
    final hasRgb = channels.any((c) => c.function.isColorMix);
    final hasPanTilt = channels.any((c) => c.function.isPanTilt);
    final hasGobo = channels.any((c) => c.function.isGobo);
    final expanded = _expanded.contains(fixture.id);
    final universeMatches = ref.watch(universesProvider).where((u) => u.id == fixture.universeId);
    final universeName = universeMatches.isEmpty ? '?' : universeMatches.first.name;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fixture.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(
                        '$universeName · Ch ${fixture.startChannel + 1}-${fixture.startChannel + channels.length}',
                        style: appMonoStyle(fontSize: 9.5, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                ),
                if (dimmerIdx != -1)
                  Switch(
                    value: values[dimmerIdx] > 0,
                    onChanged: (_) => _togglePower(fixture),
                  ),
                IconButton(
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                  tooltip: expanded ? 'Show less' : 'Show all channels',
                  onPressed: () => setState(() {
                    if (expanded) {
                      _expanded.remove(fixture.id);
                    } else {
                      _expanded.add(fixture.id);
                    }
                  }),
                ),
              ],
            ),
            if (dimmerIdx != -1)
              ChannelSliderTile(
                label: 'Dimmer',
                value: values[dimmerIdx],
                color: AppColors.accent,
                onChanged: (v) => _setChannel(fixture, dimmerIdx, v),
              ),
            if (hasRgb && !expanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in colorPresets.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _applyColor(fixture, entry.value),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, entry.value[0], entry.value[1], entry.value[2]),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasPanTilt && !expanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Pan ${_valueForFunction(fixture, ChannelFunction.pan) ?? 0}'
                  ' · Tilt ${_valueForFunction(fixture, ChannelFunction.tilt) ?? 0}'
                  '${hasGobo ? ' · Gobo ${_valueForFunction(fixture, ChannelFunction.gobo) ?? 0}' : ''}',
                  style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
                ),
              ),
            if (expanded)
              for (var i = 0; i < channels.length; i++)
                if (i != dimmerIdx)
                  ChannelSliderTile(
                    label: channels[i].label,
                    value: values[i],
                    color: _colorForFunction(channels[i].function),
                    onChanged: (v) => _setChannel(fixture, i, v),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fixtures = ref.watch(patchedFixturesProvider);
    final universes = ref.watch(universesProvider);
    final filtered = _universeFilter == null
        ? fixtures
        : fixtures.where((f) => f.universeId == _universeFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Control'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppColors.danger, width: 1.5),
              avatar: const Icon(Icons.circle, size: 8, color: AppColors.danger),
              label: const Text(
                'LIVE',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 10),
              ),
            ),
          ),
        ],
      ),
      body: fixtures.isEmpty
          ? const Center(
              child: Text('No patched fixtures — patch one in the Fixtures tab', style: TextStyle(color: AppColors.textFaint)),
            )
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All Universes'),
                          selected: _universeFilter == null,
                          onSelected: (_) => setState(() => _universeFilter = null),
                        ),
                      ),
                      for (final universe in universes)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(universe.name),
                            selected: _universeFilter == universe.id,
                            onSelected: (_) => setState(() => _universeFilter = universe.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildFixtureCard(filtered[index]),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.danger,
        tooltip: 'Blackout',
        onPressed: _blackout,
        child: const Icon(Icons.power_settings_new, color: Colors.white),
      ),
    );
  }
}

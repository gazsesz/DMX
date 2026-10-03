import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/positions/group_positions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/bank_picker_dialog.dart';
import '../../core/widgets/channel_slider.dart';
import '../../core/widgets/color_picker_dialog.dart';
import '../../core/widgets/fixture_group_style.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_channel.dart';
import '../../models/fixture_group.dart';
import '../../models/group_position.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/universe_config.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/color_palette_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/stage_providers.dart';
import 'widgets/position_panel.dart';
import 'widgets/wheel_pickers.dart';

/// A set of fixtures within a scene that share one set of channel values —
/// lets a scene mix looks, e.g. three fixtures purple and a fourth dark.
class _Group {
  final String id;
  final Set<String> fixtureIds;

  /// Channel values by channel key (see [channelKeysFor]) — mostly the
  /// function name, so `pan`, `dimmer`; generic channels by their label.
  final Map<String, int> values;

  /// Attribute groups this group deliberately leaves out of the saved scene
  /// — e.g. a color/gobo chase that excludes Position so a moving head's
  /// pan/tilt keeps whatever another program (another Layer, or manual
  /// control) is driving it to, instead of snapping to whatever this scene
  /// happens to hold.
  final Set<AttributeGroup> excluded;

  /// Fan, per-head positions and stage aim on top of the shared pan/tilt in
  /// [values].
  GroupPosition position = const GroupPosition();

  _Group({
    required this.id,
    required this.fixtureIds,
    required this.values,
    Set<AttributeGroup>? excluded,
  }) : excluded = excluded ?? {};
}

/// One distinct channel across a group's fixtures, for laying out controls.
class _Slot {
  final String key;
  final ChannelFunction function;
  final String label;
  final List<ChannelCapability> capabilities;

  const _Slot(this.key, this.function, this.label, this.capabilities);
}

/// The tabs a mover group's card splits into.
enum _MoverTab {
  position('Position'),
  color('Color'),
  gobo('Gobo'),
  prism('Prism'),
  beam('Beam'),
  channels('Channels');

  final String label;
  const _MoverTab(this.label);
}

const _newGroupSentinel = '__new_group__';

const _positionKeys = ['pan', 'panFine', 'tilt', 'tiltFine'];

class SceneEditorScreen extends ConsumerStatefulWidget {
  final Scene? existing;

  /// The bank and slot the editor was opened from, when it was opened from
  /// a bank. A copy made with Duplicate then goes into that bank, next to
  /// the original; opened from anywhere else, a copy is left unfiled.
  final String? fromBankId;
  final int? fromSlot;

  const SceneEditorScreen({super.key, this.existing, this.fromBankId, this.fromSlot});

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

  /// Which tab each mover group's card is showing.
  final Map<String, _MoverTab> _tabs = {};

  /// Where each group's heads were last resolved to, so stage aiming keeps
  /// turning them the same way round from one drag to the next.
  final Map<String, Map<String, PanTilt>> _lastResolved = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? 'New Scene');
    final scene = widget.existing;
    if (scene != null) {
      final allFixtures = ref.read(patchedFixturesProvider);
      final perFixtureValues = <String, Map<String, int>>{};
      final perFixtureExcluded = <String, Set<AttributeGroup>>{};
      for (final entry in scene.fixtureValues.entries) {
        final fixture = allFixtures.where((f) => f.id == entry.key).firstOrNull;
        if (fixture == null) continue;
        final channels = fixture.profile.channels;
        final keys = channelKeysFor(channels);
        final map = <String, int>{};
        final possibleGroups = <AttributeGroup>{};
        final presentGroups = <AttributeGroup>{};
        for (var i = 0; i < channels.length; i++) {
          final channel = channels[i];
          possibleGroups.add(channel.function.attributeGroup);
          final value = entry.value[channel.offset];
          if (value == null) continue;
          map[keys[i]] = value;
          presentGroups.add(channel.function.attributeGroup);
        }
        perFixtureValues[fixture.id] = map;
        perFixtureExcluded[fixture.id] = possibleGroups.difference(presentGroups);
        _lastKnownValues[fixture.id] = map;
      }

      final savedGroups = scene.fixtureGroups;
      if (savedGroups != null && savedGroups.isNotEmpty) {
        // Rebuild exactly the groups the user last left the scene in,
        // instead of re-clustering by value — two groups that happen to
        // share a colour (or one split off before its colour changed) must
        // not silently re-merge on reopen, or the grouping looks like it
        // never saved.
        final savedPositions = scene.groupPositions;
        for (var g = 0; g < savedGroups.length; g++) {
          final present = savedGroups[g].where(perFixtureValues.containsKey).toSet();
          if (present.isEmpty) continue;
          final representative = perFixtureValues[present.first]!;
          final excluded = perFixtureExcluded[present.first]!;
          final group = _Group(
            id: 'g${_groupCounter++}',
            fixtureIds: present,
            values: Map.of(representative),
            excluded: Set.of(excluded),
          );
          final saved = savedPositions != null && g < savedPositions.length ? savedPositions[g] : null;
          if (saved != null) {
            group.position = saved;
            // The representative fixture's values hold its own fanned
            // position; put the pad back on the one the group fans out from.
            final base = saved.base;
            if (base != null) _writeBase(group.values, base);
          }
          _groups.add(group);
        }
        // Any fixture the scene has values for but that wasn't listed in a
        // saved group (older data, or one added since) still gets to show
        // up — on its own, clustered with whichever others match its exact
        // look, same as the old behaviour.
        final grouped = {for (final g in _groups) ...g.fixtureIds};
        final orphans = perFixtureValues.keys.where((id) => !grouped.contains(id));
        _clusterByValue(orphans, perFixtureValues, perFixtureExcluded);
      } else {
        // No saved grouping (older scene, or one built programmatically,
        // e.g. the Beat Flash preset) — cluster fixtures that share an
        // identical value map (and the same excluded attribute groups) into
        // one group, so a previously-saved "3 purple, 1 dark" scene re-opens
        // that way.
        _clusterByValue(perFixtureValues.keys, perFixtureValues, perFixtureExcluded);
      }
    }
  }

  /// Groups fixtures in [ids] by exactly matching channel values and
  /// excluded attribute groups — the fallback for scenes with no explicit
  /// saved grouping.
  void _clusterByValue(
    Iterable<String> ids,
    Map<String, Map<String, int>> perFixtureValues,
    Map<String, Set<AttributeGroup>> perFixtureExcluded,
  ) {
    final byValues = <String, _Group>{};
    for (final fixtureId in ids) {
      final map = perFixtureValues[fixtureId]!;
      final excluded = perFixtureExcluded[fixtureId]!;
      final values = (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}:${e.value}')
          .join(',');
      final key = '$values|${(excluded.toList()..sort((a, b) => a.index.compareTo(b.index))).join(',')}';
      final group = byValues.putIfAbsent(
        key,
        () => _Group(id: 'g${_groupCounter++}', fixtureIds: {}, values: Map.of(map), excluded: Set.of(excluded)),
      );
      group.fixtureIds.add(fixtureId);
    }
    _groups.addAll(byValues.values);
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

  /// Every distinct channel across the group, one entry per key, ordered by
  /// function the way the faders always were.
  List<_Slot> _slotsFor(_Group group) {
    final slots = <String, _Slot>{};
    for (final fixture in _fixturesIn(group)) {
      final channels = fixture.profile.channels;
      final keys = channelKeysFor(channels);
      for (var i = 0; i < channels.length; i++) {
        final existing = slots[keys[i]];
        if (existing == null || (existing.capabilities.isEmpty && channels[i].hasCapabilities)) {
          slots[keys[i]] = _Slot(keys[i], channels[i].function, channels[i].label, channels[i].capabilities);
        }
      }
    }
    final ordered = slots.values.toList();
    final firstSeen = {for (var i = 0; i < ordered.length; i++) ordered[i].key: i};
    ordered.sort((a, b) {
      final byFunction = a.function.index.compareTo(b.function.index);
      return byFunction != 0 ? byFunction : firstSeen[a.key]!.compareTo(firstSeen[b.key]!);
    });
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

  /// Adds a whole saved [FixtureGroup] as one new scene group in a single
  /// tap — skips any fixture that's already selected, since it's already
  /// live somewhere and re-grouping it should stay a deliberate drag, not a
  /// side effect of tapping a shortcut chip.
  void _addSavedGroupToScene(FixtureGroup savedGroup) {
    final patchedIds = _allFixtures.map((f) => f.id).toSet();
    final selected = _selectedFixtureIds;
    final ids = savedGroup.fixtureIds.where((id) => patchedIds.contains(id) && !selected.contains(id)).toSet();
    if (ids.isEmpty) return;
    setState(() {
      final values = <String, int>{};
      for (final id in ids) {
        final cached = _lastKnownValues[id];
        if (cached != null) {
          values.addAll(cached);
          break;
        }
      }
      _groups.add(_Group(id: 'g${_groupCounter++}', fixtureIds: ids, values: values));
    });
  }

  /// Takes [fixtureId] out of [group], forgetting any position it had there
  /// on its own.
  void _detach(_Group group, String fixtureId) {
    group.fixtureIds.remove(fixtureId);
    final position = group.position;
    if (position.manual.containsKey(fixtureId) || position.aimOverrides.containsKey(fixtureId)) {
      group.position = position.copyWith(
        manual: {...position.manual}..remove(fixtureId),
        aimOverrides: {...position.aimOverrides}..remove(fixtureId),
      );
    }
    if (group.fixtureIds.isEmpty) _groups.remove(group);
  }

  void _removeFixtureFromScene(PatchedFixture fixture) {
    setState(() {
      final group = _groupOf(fixture.id);
      if (group == null) return;
      _lastKnownValues[fixture.id] = _valuesForFixture(group, fixture);
      _detach(group, fixture.id);
    });
  }

  void _reassignFixture(PatchedFixture fixture, String targetGroupId) {
    setState(() {
      final current = _groupOf(fixture.id);
      if (current != null) {
        _lastKnownValues[fixture.id] = _valuesForFixture(current, fixture);
        _detach(current, fixture.id);
      }
      if (targetGroupId == _newGroupSentinel) {
        final cached = _lastKnownValues[fixture.id];
        _groups.add(
          _Group(id: 'g${_groupCounter++}', fixtureIds: {fixture.id}, values: cached != null ? Map.of(cached) : {}),
        );
      } else {
        final target = _groups.where((g) => g.id == targetGroupId).firstOrNull;
        if (target != null) {
          target.fixtureIds.add(fixture.id);
          // The fixture now shows the target group's look, not whatever it
          // had before — cache that, or moving it again later (e.g. back
          // out to its own group) would resurrect the stale value instead
          // of the colour it's actually showing.
          _lastKnownValues[fixture.id] = Map.of(target.values);
        }
      }
    });
  }

  int _valueForInGroup(_Group group, ChannelFunction function) => group.values[function.name] ?? 0;

  /// The declared value ranges for [function] across the group's fixtures.
  ///
  /// A group can mix fixture types, and one fader drives them all, so the
  /// first fixture that declares ranges for this function names the options.
  /// Mixed-profile groups therefore show one fixture's labels — accepted:
  /// the alternative is showing no names at all for the common case where
  /// every fixture in the group is the same model.
  List<ChannelCapability> _capabilitiesFor(_Group group, ChannelFunction function) {
    for (final fixture in _fixturesIn(group)) {
      for (final channel in fixture.profile.channels) {
        if (channel.function == function && channel.hasCapabilities) return channel.capabilities;
      }
    }
    return const [];
  }

  /// Which attribute groups this group's fixtures actually have a channel
  /// for — only these get a toggle, so a fixture with no Position channels
  /// never shows a "Position" switch it couldn't do anything with.
  Set<AttributeGroup> _availableGroupsFor(_Group group) =>
      {for (final function in _sharedFunctionsFor(group)) function.attributeGroup};

  void _toggleAttributeGroup(_Group group, AttributeGroup attributeGroup) {
    setState(() {
      if (group.excluded.contains(attributeGroup)) {
        group.excluded.remove(attributeGroup);
      } else {
        group.excluded.add(attributeGroup);
      }
    });
    _pushLiveOutput();
  }

  void _rememberGroupValues(_Group group) {
    for (final id in group.fixtureIds) {
      _lastKnownValues[id] = Map.of(group.values);
    }
  }

  void _setKeyInGroup(_Group group, String key, int value) {
    setState(() => group.values[key] = value.clamp(0, 255));
    _rememberGroupValues(group);
    _pushLiveOutput();
  }

  void _setValueInGroup(_Group group, ChannelFunction function, int value) =>
      _setKeyInGroup(group, function.name, value);

  // ---- position ---------------------------------------------------------------

  static void _writeBase(Map<String, int> values, PanTilt base) {
    values['pan'] = base.panCoarse;
    values['panFine'] = base.panFine;
    values['tilt'] = base.tiltCoarse;
    values['tiltFine'] = base.tiltFine;
  }

  /// The group's shared pan/tilt. A group nobody has positioned yet sits at
  /// the centre of travel, which is also what gets saved for it.
  PanTilt _baseOf(_Group group) {
    final v = group.values;
    if (!v.containsKey('pan') && !v.containsKey('tilt')) return PanTilt.center;
    return PanTilt.fromChannels(
      pan: v['pan'] ?? 128,
      panFine: v['panFine'] ?? 0,
      tilt: v['tilt'] ?? 128,
      tiltFine: v['tiltFine'] ?? 0,
    );
  }

  List<PatchedFixture> _moversIn(_Group group) =>
      _fixturesIn(group).where((f) => f.profile.channels.any((c) => c.function.isPanTilt)).toList();

  /// Where each head of [group] actually points, fan and aim included.
  Map<String, ResolvedPosition> _resolvedFor(_Group group) {
    final movers = _moversIn(group);
    if (movers.isEmpty) return const {};
    final resolved = resolveGroupPositions(
      position: group.position,
      base: _baseOf(group),
      fixtures: movers,
      stage: ref.read(stagePlanProvider),
      previous: _lastResolved[group.id] ?? const {},
    );
    _lastResolved[group.id] = {for (final e in resolved.entries) e.key: e.value.position};
    return resolved;
  }

  /// The values [fixture] actually gets from [group]: the group's, with the
  /// head's own resolved pan/tilt in place of the shared one.
  Map<String, int> _valuesForFixture(_Group group, PatchedFixture fixture, [Map<String, ResolvedPosition>? resolved]) {
    final values = Map.of(group.values);
    final own = (resolved ?? _resolvedFor(group))[fixture.id];
    if (own != null) _writeBase(values, own.position);
    return values;
  }

  void _dragBase(_Group group, PanTilt to) {
    setState(() {
      final delta = to - _baseOf(group);
      group.position = shiftManual(group.position, delta);
      _writeBase(group.values, to.clamped());
    });
    _rememberGroupValues(group);
    _pushLiveOutput();
  }

  void _replacePosition(_Group group, PanTilt base, GroupPosition position) {
    setState(() {
      group.position = position;
      _writeBase(group.values, base.clamped());
    });
    _rememberGroupValues(group);
    _pushLiveOutput();
  }

  // ---- colour -----------------------------------------------------------------

  void _applyColorToGroup(_Group group, List<int> rgb) {
    setState(() {
      group.values[ChannelFunction.red.name] = rgb[0];
      group.values[ChannelFunction.green.name] = rgb[1];
      group.values[ChannelFunction.blue.name] = rgb[2];
      final hasDimmer = _sharedFunctionsFor(group).contains(ChannelFunction.dimmer);
      if (hasDimmer && (group.values[ChannelFunction.dimmer.name] ?? 0) == 0) {
        group.values[ChannelFunction.dimmer.name] = 255;
      }
      _rememberGroupValues(group);
    });
    _pushLiveOutput();
  }

  /// Opens the full picker — presets, your saved colours, and a palette to
  /// mix a new one.
  ///
  /// The rig follows the sliders while it's open, so you pick by looking at
  /// the lamps; dismissing it puts the group back exactly as it was, live
  /// output included, rather than leaving the last colour you dragged past.
  Future<void> _openColorPicker(_Group group) async {
    final snapshot = Map.of(group.values);
    final picked = await showColorPickerDialog(
      context,
      initial: [
        _valueForInGroup(group, ChannelFunction.red),
        _valueForInGroup(group, ChannelFunction.green),
        _valueForInGroup(group, ChannelFunction.blue),
      ],
      onPreview: (rgb) => _applyColorToGroup(group, rgb),
    );
    if (!mounted) return;
    if (picked != null) {
      _applyColorToGroup(group, picked);
      return;
    }
    setState(() {
      group.values
        ..clear()
        ..addAll(snapshot);
      _rememberGroupValues(group);
    });
    _pushLiveOutput();
  }

  // ---- output -----------------------------------------------------------------

  void _pushLiveOutput() {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    final universes = ref.read(universesProvider);
    final touched = <UniverseConfig>{};
    for (final group in _groups) {
      final resolved = _resolvedFor(group);
      for (final fixture in _fixturesIn(group)) {
        final universeMatches = universes.where((u) => u.id == fixture.universeId);
        if (universeMatches.isEmpty) continue;
        final universe = universeMatches.first;
        touched.add(universe);
        final channels = fixture.profile.channels;
        final keys = channelKeysFor(channels);
        final values = _valuesForFixture(group, fixture, resolved);
        for (var i = 0; i < channels.length; i++) {
          final channel = channels[i];
          if (group.excluded.contains(channel.function.attributeGroup)) continue;
          final value = values[keys[i]];
          if (value == null) continue;
          service.setChannel(universe, fixture.startChannel + channel.offset, value, send: false);
        }
      }
    }
    for (final universe in touched) {
      service.flush(universe);
    }
  }

  Map<String, Map<int, int>> _buildFixtureValues() {
    final result = <String, Map<int, int>>{};
    for (final group in _groups) {
      final resolved = _resolvedFor(group);
      for (final fixture in _fixturesIn(group)) {
        final values = <int, int>{};
        final channels = fixture.profile.channels;
        final keys = channelKeysFor(channels);
        final own = _valuesForFixture(group, fixture, resolved);
        for (var i = 0; i < channels.length; i++) {
          final channel = channels[i];
          if (group.excluded.contains(channel.function.attributeGroup)) continue;
          values[channel.offset] = own[keys[i]] ?? 0;
        }
        result[fixture.id] = values;
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
      final value = _valueForInGroup(group, ChannelFunction.gobo);
      return 'Gobo: ${goboLabelFor(_capabilitiesFor(group, ChannelFunction.gobo), value)}';
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

  /// Saves and hands the scene back to whoever opened the editor.
  ///
  /// The Banks screen relies on that return value: creating a scene from an
  /// empty slot should drop it straight into that slot, rather than making
  /// you go and find it in a list afterwards.
  List<List<String>> get _fixtureGroupsForSave => [for (final g in _groups) g.fixtureIds.toList()];

  List<GroupPosition?> get _groupPositionsForSave => [
    for (final g in _groups)
      g.position.isPlain || _moversIn(g).isEmpty ? null : g.position.copyWith(base: _baseOf(g)),
  ];

  /// Saves what's on screen as a new scene and carries on editing that copy.
  ///
  /// The original keeps whatever it was last saved as, so this doubles as
  /// "save as": tweak a look, duplicate, and both versions exist.
  void _duplicate() {
    if (_selectedFixtureIds.isEmpty) return;
    final name = _nameController.text.trim().isEmpty ? 'Scene' : _nameController.text.trim();
    final notifier = ref.read(scenesProvider.notifier);
    final copy = notifier
        .create('$name Copy', _buildFixtureValues())
        .copyWith(fixtureGroups: _fixtureGroupsForSave, groupPositions: _groupPositionsForSave);
    notifier.upsert(copy);

    final bankId = widget.fromBankId;
    final slot = bankId == null ? null : ref.read(banksProvider.notifier).placeAfter(bankId, widget.fromSlot, copy.id);
    final bankName = bankId == null ? null : ref.read(banksProvider).where((b) => b.id == bankId).firstOrNull?.name;
    final filed = slot == null ? '' : ' Added to $bankName, slot ${slot + 1}.';

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        // Still "from the bank", now from the copy's slot — so duplicating
        // again lines the next copy up after this one.
        builder: (_) => SceneEditorScreen(existing: copy, fromBankId: slot == null ? null : bankId, fromSlot: slot),
      ),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved as "${copy.name}" — you\'re editing the copy now. "$name" is unchanged.$filed'),
      ),
    );
  }

  void _save() {
    if (_selectedFixtureIds.isEmpty || _nameController.text.trim().isEmpty) return;
    final fixtureValues = _buildFixtureValues();
    final fixtureGroups = _fixtureGroupsForSave;
    final groupPositions = _groupPositionsForSave;
    final notifier = ref.read(scenesProvider.notifier);
    final Scene saved;
    if (widget.existing != null) {
      saved = widget.existing!.copyWith(
        name: _nameController.text.trim(),
        fixtureValues: fixtureValues,
        fixtureGroups: fixtureGroups,
        groupPositions: groupPositions,
      );
      notifier.upsert(saved);
    } else {
      saved = notifier
          .create(_nameController.text.trim(), fixtureValues)
          .copyWith(fixtureGroups: fixtureGroups, groupPositions: groupPositions);
      notifier.upsert(saved);
    }
    Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text('Delete "${existing.name}"?'),
        content: const Text('This also removes it from any bank slots it\'s assigned to.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(scenesProvider.notifier).remove(existing.id);
    Navigator.of(context).pop();
  }

  Future<void> _assignToBank() async {
    if (widget.existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the scene first')),
      );
      return;
    }
    final bankId = await showBankPicker(context);
    if (bankId == null || !mounted) return;
    final message = assignSceneToBank(ref, bankId: bankId, sceneId: widget.existing!.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ---- group card ---------------------------------------------------------------

  /// Whether [functions] belong to a mover worth the tabbed card. A plain
  /// RGB par group keeps the original one-screen layout.
  bool _isMoverGroup(List<ChannelFunction> functions) => functions.any(
    (f) => f.isPanTilt || f.isGobo || f.isPrism || f == ChannelFunction.colorWheel || f == ChannelFunction.frost,
  );

  Widget _buildGroupCard(_Group group, int index) {
    final functions = _sharedFunctionsFor(group);
    final fixtures = _fixturesIn(group);
    final availableGroups = _availableGroupsFor(group).toList()..sort((a, b) => a.index.compareTo(b.index));

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
            Text(
              'Group ${index + 1} · ${_describeGroup(group)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
            if (availableGroups.length > 1) ...[
              const SizedBox(height: 10),
              const Text(
                'INCLUDES',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textFaint),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final attributeGroup in availableGroups)
                    FilterChip(
                      label: Text(attributeGroup.label, style: const TextStyle(fontSize: 10.5)),
                      selected: !group.excluded.contains(attributeGroup),
                      onSelected: (_) => _toggleAttributeGroup(group, attributeGroup),
                      tooltip: group.excluded.contains(attributeGroup)
                          ? 'Left alone at playback — another program can drive it'
                          : 'This scene sets it',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (_isMoverGroup(functions)) _buildMoverBody(group, functions) else _buildPlainBody(group, functions),
          ],
        ),
      ),
    );
  }

  /// The original card body: colour swatches on the left, pan/tilt and gobo
  /// shortcuts plus a fader per channel on the right.
  Widget _buildPlainBody(_Group group, List<ChannelFunction> functions) {
    final hasColor = functions.any((f) => f.isColorMix);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasColor) SizedBox(width: 216, child: _rgbSwatches(group)),
        if (hasColor) const SizedBox(width: 16),
        Expanded(child: _channelFaders(group)),
      ],
    );
  }

  Widget _rgbSwatches(_Group group) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in colorPresets.entries)
          _ColorSwatch(
            rgb: entry.value,
            tooltip: entry.key,
            onTap: () => _applyColorToGroup(group, entry.value),
          ),
        // Your own colours sit in the same grid as the presets rather than
        // in a drawer of their own — once saved, a house colour is just a
        // colour.
        for (final colour in ref.watch(customColorsProvider))
          _ColorSwatch(
            rgb: colour.rgb,
            tooltip: colour.displayName,
            onTap: () => _applyColorToGroup(group, colour.rgb),
          ),
        Tooltip(
          message: 'Mix a colour',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openColorPicker(group),
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.panel2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
              child: const Icon(Icons.palette_outlined, size: 20, color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  /// A fader for every channel the group has, named by the channel's own
  /// label (so a profile's Prism, Frost and Reset are three faders, not
  /// three copies of "Generic").
  Widget _channelFaders(_Group group) {
    return Wrap(
      spacing: 6,
      runSpacing: 10,
      children: [
        for (final slot in _slotsFor(group))
          ChannelSliderTile(
            label: slot.label,
            value: group.values[slot.key] ?? (_positionKeys.contains(slot.key) ? _defaultPositionValue(slot.key) : 0),
            color: slot.function.isPanTilt || slot.function.isGobo || slot.function.isPrism
                ? AppColors.accent2
                : AppColors.accent,
            capabilities: slot.capabilities,
            onChanged: (v) => _setSlot(group, slot.key, v),
          ),
      ],
    );
  }

  int _defaultPositionValue(String key) => key == 'pan' || key == 'tilt' ? 128 : 0;

  /// A fader that moves pan or tilt moves the shared position like the pad,
  /// so heads set on their own stay with it.
  void _setSlot(_Group group, String key, int value) {
    if (!_positionKeys.contains(key)) {
      _setKeyInGroup(group, key, value);
      return;
    }
    final base = _baseOf(group);
    final values = <String, int>{};
    _writeBase(values, base);
    values[key] = value.clamp(0, 255);
    _dragBase(
      group,
      PanTilt.fromChannels(
        pan: values['pan']!,
        panFine: values['panFine']!,
        tilt: values['tilt']!,
        tiltFine: values['tiltFine']!,
      ),
    );
  }

  List<_MoverTab> _tabsFor(List<ChannelFunction> functions) => [
    if (functions.any((f) => f.isPanTilt)) _MoverTab.position,
    if (functions.any((f) => f.isColorMix || f == ChannelFunction.colorWheel)) _MoverTab.color,
    if (functions.any((f) => f.isGobo)) _MoverTab.gobo,
    if (functions.any((f) => f.isPrism)) _MoverTab.prism,
    if (functions.any(_isBeamFunction)) _MoverTab.beam,
    _MoverTab.channels,
  ];

  static bool _isBeamFunction(ChannelFunction f) =>
      f == ChannelFunction.dimmer ||
      f == ChannelFunction.strobe ||
      f == ChannelFunction.zoom ||
      f == ChannelFunction.focus ||
      f == ChannelFunction.frost;

  /// What each tab is set to, shown next to its name so a collapsed card
  /// still reads at a glance.
  String _tabSummary(_Group group, _MoverTab tab, List<ChannelFunction> functions) {
    String nameOf(ChannelFunction f) {
      final caps = _capabilitiesFor(group, f);
      final value = _valueForInGroup(group, f);
      for (final c in caps) {
        if (c.contains(value)) return c.label;
      }
      return '$value';
    }

    switch (tab) {
      case _MoverTab.position:
        final position = group.position;
        if (position.mode == PositionMode.stage) return 'Stage';
        if (position.manual.isNotEmpty) return 'Preset';
        if (position.fanPanDeg != 0 || position.fanTiltDeg != 0) return 'Fan';
        final range = _moversIn(group).firstOrNull?.profile.panRangeDeg ?? 540;
        return '${(_baseOf(group).pan / PanTilt.max * range).round()}°';
      case _MoverTab.color:
        if (functions.contains(ChannelFunction.colorWheel)) return nameOf(ChannelFunction.colorWheel);
        return _describeGroup(group);
      case _MoverTab.gobo:
        return goboLabelFor(_capabilitiesFor(group, ChannelFunction.gobo), _valueForInGroup(group, ChannelFunction.gobo));
      case _MoverTab.prism:
        return functions.contains(ChannelFunction.prism) ? nameOf(ChannelFunction.prism) : '';
      case _MoverTab.beam:
        if (!functions.contains(ChannelFunction.dimmer)) return '';
        return 'Dim ${(_valueForInGroup(group, ChannelFunction.dimmer) / 255 * 100).round()}%';
      case _MoverTab.channels:
        return '${_slotsFor(group).length}';
    }
  }

  AttributeGroup? _attributeOf(_MoverTab tab) => switch (tab) {
    _MoverTab.position => AttributeGroup.position,
    _MoverTab.gobo || _MoverTab.prism => AttributeGroup.beam,
    _ => null,
  };

  Widget _buildMoverBody(_Group group, List<ChannelFunction> functions) {
    final tabs = _tabsFor(functions);
    final current = tabs.contains(_tabs[group.id]) ? _tabs[group.id]! : tabs.first;
    final attribute = _attributeOf(current);
    final leftOut = attribute != null && group.excluded.contains(attribute);

    Widget body = switch (current) {
      _MoverTab.position => _positionTab(group, functions),
      _MoverTab.color => _colorTab(group, functions),
      _MoverTab.gobo => _goboTab(group, functions),
      _MoverTab.prism => _prismTab(group, functions),
      _MoverTab.beam => _beamTab(group, functions),
      _MoverTab.channels => _channelFaders(group),
    };
    if (leftOut) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${attribute.label} is left out of this scene — turn it on under INCLUDES to set it here.',
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          IgnorePointer(child: Opacity(opacity: 0.35, child: body)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in tabs)
                _TabButton(
                  label: tab.label,
                  summary: _tabSummary(group, tab, functions),
                  selected: tab == current,
                  onTap: () => setState(() => _tabs[group.id] = tab),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 12),
        body,
      ],
    );
  }

  Widget _positionTab(_Group group, List<ChannelFunction> functions) {
    final hasSpeed = functions.contains(ChannelFunction.panTiltSpeed);
    return PositionPanel(
      fixtures: _moversIn(group),
      base: _baseOf(group),
      position: group.position,
      resolved: _resolvedFor(group),
      speed: hasSpeed ? _valueForInGroup(group, ChannelFunction.panTiltSpeed) : null,
      speedCapabilities: _capabilitiesFor(group, ChannelFunction.panTiltSpeed),
      onBaseDragged: (to) => _dragBase(group, to),
      onReplace: (base, position) => _replacePosition(group, base, position),
      onSpeedChanged: (v) => _setValueInGroup(group, ChannelFunction.panTiltSpeed, v),
      onRiggingChanged: () {
        if (!mounted) return;
        setState(() {});
        _pushLiveOutput();
      },
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
  );

  /// A horizontal slider for [function], or nothing when the group has no
  /// such channel.
  Widget? _sliderFor(_Group group, List<ChannelFunction> functions, ChannelFunction function, {String? label}) {
    if (!functions.contains(function)) return null;
    return LabeledChannelSlider(
      label: label ?? function.label,
      value: _valueForInGroup(group, function),
      color: AppColors.accent2,
      capabilities: _capabilitiesFor(group, function),
      onChanged: (v) => _setValueInGroup(group, function, v),
    );
  }

  Widget _colorTab(_Group group, List<ChannelFunction> functions) {
    final hasRgb = functions.any((f) => f.isColorMix);
    final wheelCaps = _capabilitiesFor(group, ChannelFunction.colorWheel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (functions.contains(ChannelFunction.colorWheel)) ...[
          _sectionLabel('COLOR WHEEL'),
          if (wheelCaps.isEmpty)
            _sliderFor(group, functions, ChannelFunction.colorWheel)!
          else
            ColorWheelPicker(
              capabilities: wheelCaps,
              value: _valueForInGroup(group, ChannelFunction.colorWheel),
              onChanged: (v) => _setValueInGroup(group, ChannelFunction.colorWheel, v),
            ),
          if (wheelCaps.isNotEmpty && wheelCaps.every((c) => c.colorHex == null))
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Swatch colours are guessed from the range names. Set them exactly in Fixtures → edit → Ranges.',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint),
              ),
            ),
        ],
        if (hasRgb) ...[
          if (functions.contains(ChannelFunction.colorWheel)) const SizedBox(height: 14),
          _sectionLabel('COLOR MIX'),
          _rgbSwatches(group),
        ],
      ],
    );
  }

  Widget _goboTab(_Group group, List<ChannelFunction> functions) {
    final rotation = _sliderFor(group, functions, ChannelFunction.goboRotation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (functions.contains(ChannelFunction.gobo))
          GoboPicker(
            capabilities: goboChoicesFor(_capabilitiesFor(group, ChannelFunction.gobo)),
            value: _valueForInGroup(group, ChannelFunction.gobo),
            onChanged: (v) => _setValueInGroup(group, ChannelFunction.gobo, v),
          ),
        if (rotation != null) ...[const SizedBox(height: 12), rotation],
      ],
    );
  }

  Widget _prismTab(_Group group, List<ChannelFunction> functions) {
    final prismCaps = _capabilitiesFor(group, ChannelFunction.prism);
    final rotation = _sliderFor(group, functions, ChannelFunction.prismRotation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (functions.contains(ChannelFunction.prism))
          if (prismCaps.isEmpty)
            _sliderFor(group, functions, ChannelFunction.prism)!
          else
            SlotChips(
              capabilities: prismCaps,
              value: _valueForInGroup(group, ChannelFunction.prism),
              onChanged: (v) => _setValueInGroup(group, ChannelFunction.prism, v),
            ),
        if (rotation != null) ...[const SizedBox(height: 12), rotation],
      ],
    );
  }

  Widget _beamTab(_Group group, List<ChannelFunction> functions) {
    final sliders = [
      for (final f in [
        ChannelFunction.dimmer,
        ChannelFunction.strobe,
        ChannelFunction.zoom,
        ChannelFunction.focus,
        ChannelFunction.frost,
      ])
        ?_sliderFor(group, functions, f),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
        return Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [for (final s in sliders) SizedBox(width: width, child: s)],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allFixtures = ref.watch(patchedFixturesProvider);
    final selected = _selectedFixtureIds;
    final savedGroups = ref.watch(fixtureGroupsProvider);
    // The stage plan's size and the head positions feed the aim maths.
    ref.watch(stagePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true),
        ),
        actions: [
          if (widget.existing != null) ...[
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _selectedFixtureIds.isEmpty ? null : _duplicate,
              tooltip: 'Duplicate',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: _delete,
              tooltip: 'Delete',
            ),
          ],
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
                if (savedGroups.isNotEmpty) ...[
                  const Text(
                    'ADD SAVED GROUP',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: savedGroups.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final group = savedGroups[index];
                        final count = group.fixtureIds.where((id) => allFixtures.any((f) => f.id == id)).length;
                        return ActionChip(
                          avatar: Icon(fixtureGroupIcon(group.iconKey), size: 16, color: fixtureGroupColor(group.iconKey)),
                          label: Text('${group.name} · $count'),
                          onPressed: () => _addSavedGroupToScene(group),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
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

/// One tab of a mover group's card: its name, and underneath, what it's set
/// to right now.
class _TabButton extends StatelessWidget {
  final String label;
  final String summary;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.summary, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.accent : AppColors.textDim,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                summary.isEmpty ? ' ' : summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: AppColors.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable colour in the group's swatch grid.
class _ColorSwatch extends StatelessWidget {
  final List<int> rgb;
  final String tooltip;
  final VoidCallback onTap;

  const _ColorSwatch({required this.rgb, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
        ),
      ),
    );
  }
}

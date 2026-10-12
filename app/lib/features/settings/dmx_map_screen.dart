import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/patched_fixture.dart';
import '../../models/universe_config.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';

const _channelsPerRow = 32;
const _universeSize = 512;

/// Colours the fixtures are told apart by, picked by patch order so a fixture
/// keeps its colour as long as the patch does.
const _fixtureColors = [
  Color(0xFF22D3EE),
  Color(0xFFF5A623),
  Color(0xFF22C55E),
  Color(0xFFA78BFA),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
  Color(0xFFFACC15),
  Color(0xFF2DD4BF),
];

/// Which channels of one universe the patched fixtures take, as the numbers
/// 1-512 a fixture's DIP switches or menu are set to.
///
/// Several fixtures on the same channel is shown in red — it's a mistake in
/// the patch more often than a choice.
class DmxMapScreen extends ConsumerStatefulWidget {
  const DmxMapScreen({super.key});

  @override
  ConsumerState<DmxMapScreen> createState() => _DmxMapScreenState();
}

class _DmxMapScreenState extends ConsumerState<DmxMapScreen> {
  String? _universeId;

  @override
  Widget build(BuildContext context) {
    final universes = ref.watch(universesProvider);
    final fixtures = ref.watch(patchedFixturesProvider);
    final universe = universes.where((u) => u.id == _universeId).firstOrNull ?? universes.first;
    final inUniverse = [for (final f in fixtures) if (f.universeId == universe.id) f];
    final layout = DmxMapLayout.of(inUniverse, fixtures);

    return Scaffold(
      appBar: AppBar(title: const Text('DMX channel map')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${layout.used} of $_universeSize channels used · ${inUniverse.length} fixtures'
                    '${layout.firstFree == null ? '' : ' · first free: ${layout.firstFree}'}',
                    style: appMonoStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
                ),
                if (layout.conflicts > 0)
                  Text(
                    '${layout.conflicts} channels overlap',
                    style: const TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Narrow screens scroll sideways rather than squeezing the
                // channel numbers into unreadable cells.
                final width = constraints.maxWidth - 16;
                final gridWidth = width < _channelsPerRow * 28.0 ? _channelsPerRow * 28.0 : width;
                final grid = SizedBox(
                  width: gridWidth,
                  child: _MapGrid(
                    layout: layout,
                    onTapFixture: (fixture) => _showFixture(context, fixture, universe),
                  ),
                );
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: gridWidth > width
                        ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid)
                        : grid,
                  ),
                );
              },
            ),
          ),
          if (universes.length > 1)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SegmentedButton<String>(
                  segments: [for (final u in universes) ButtonSegment(value: u.id, label: Text(u.name))],
                  selected: {universe.id},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _universeId = s.first),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showFixture(BuildContext context, PatchedFixture fixture, UniverseConfig universe) {
    final first = fixture.startChannel + 1;
    final last = fixture.startChannel + fixture.profile.channelCount;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(fixture.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              '${fixture.profile.name} · ${universe.name} · channels $first–$last '
              '(${fixture.profile.channelCount})',
              style: appMonoStyle(fontSize: 11, color: AppColors.textFaint),
            ),
            const SizedBox(height: 10),
            for (final channel in fixture.profile.channels)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text('${fixture.startChannel + channel.offset + 1}', style: appMonoStyle(fontSize: 12)),
                    ),
                    Expanded(child: Text(channel.label, style: const TextStyle(fontSize: 13))),
                    Text('+${channel.offset + 1}', style: appMonoStyle(fontSize: 11, color: AppColors.textFaint)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A run of neighbouring channels in one row of the map that belong together:
/// all one fixture, all free, or all overlapping.
class MapSegment {
  /// 0-based first channel and how many.
  final int start;
  final int length;
  final PatchedFixture? fixture;
  final bool conflict;

  /// The first row segment of its fixture — where its name goes.
  final bool isHead;

  const MapSegment({
    required this.start,
    required this.length,
    required this.fixture,
    required this.conflict,
    required this.isHead,
  });

  int get end => start + length - 1;
}

/// What the map draws, worked out from the patch.
class DmxMapLayout {
  final List<List<MapSegment>> rows;
  final int used;
  final int conflicts;

  /// 1-based number of the first unused channel, or null when all are taken.
  final int? firstFree;

  /// Colour index of a fixture, by its place in the whole patch.
  final Map<String, int> colorIndex;

  const DmxMapLayout({
    required this.rows,
    required this.used,
    required this.conflicts,
    required this.firstFree,
    required this.colorIndex,
  });

  static DmxMapLayout of(List<PatchedFixture> inUniverse, List<PatchedFixture> wholePatch) {
    final owners = List<List<PatchedFixture>>.generate(_universeSize, (_) => []);
    for (final fixture in inUniverse) {
      for (var i = 0; i < fixture.profile.channelCount; i++) {
        final channel = fixture.startChannel + i;
        if (channel >= 0 && channel < _universeSize) owners[channel].add(fixture);
      }
    }

    final seenFixtures = <String>{};
    final rows = <List<MapSegment>>[];
    for (var row = 0; row < _universeSize ~/ _channelsPerRow; row++) {
      final segments = <MapSegment>[];
      var channel = row * _channelsPerRow;
      final rowEnd = channel + _channelsPerRow;
      while (channel < rowEnd) {
        final here = owners[channel];
        final fixture = here.length == 1 ? here.first : null;
        final conflict = here.length > 1;
        var end = channel;
        while (end + 1 < rowEnd) {
          final next = owners[end + 1];
          final sameKind = conflict
              ? next.length > 1
              : (fixture == null ? next.isEmpty : next.length == 1 && next.first.id == fixture.id);
          if (!sameKind) break;
          end++;
        }
        // A free channel stays its own cell, so each can be read off the grid.
        if (fixture == null && !conflict) {
          for (var c = channel; c <= end; c++) {
            segments.add(MapSegment(start: c, length: 1, fixture: null, conflict: false, isHead: false));
          }
        } else {
          final head = fixture != null && seenFixtures.add(fixture.id);
          segments.add(MapSegment(
            start: channel,
            length: end - channel + 1,
            fixture: fixture ?? here.first,
            conflict: conflict,
            isHead: head || conflict,
          ));
        }
        channel = end + 1;
      }
      rows.add(segments);
    }

    return DmxMapLayout(
      rows: rows,
      used: owners.where((o) => o.isNotEmpty).length,
      conflicts: owners.where((o) => o.length > 1).length,
      firstFree: owners.indexWhere((o) => o.isEmpty) == -1 ? null : owners.indexWhere((o) => o.isEmpty) + 1,
      colorIndex: {for (var i = 0; i < wholePatch.length; i++) wholePatch[i].id: i},
    );
  }
}

class _MapGrid extends StatelessWidget {
  final DmxMapLayout layout;
  final ValueChanged<PatchedFixture> onTapFixture;

  const _MapGrid({required this.layout, required this.onTapFixture});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          for (final row in layout.rows)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  for (final segment in row)
                    Expanded(flex: segment.length, child: _cell(segment)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(MapSegment segment) {
    final fixture = segment.fixture;
    if (fixture == null) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: AppColors.border, width: 0.5)),
        child: Text(
          '${segment.start + 1}',
          style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
      );
    }
    final color = segment.conflict
        ? AppColors.danger
        : _fixtureColors[(layout.colorIndex[fixture.id] ?? 0) % _fixtureColors.length];
    final label = segment.conflict ? 'overlap' : fixture.label;
    return InkWell(
      onTap: () => onTapFixture(fixture),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${segment.start + 1}', style: appMonoStyle(fontSize: 10.5, color: AppColors.text)),
            ),
            if (segment.length > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Text('${segment.end + 1}', style: appMonoStyle(fontSize: 10.5, color: AppColors.text)),
              ),
            if (segment.length >= 4)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Text(
                  segment.isHead ? label : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

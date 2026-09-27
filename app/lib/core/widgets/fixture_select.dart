import 'package:flutter/material.dart';

import '../../models/fixture_profile.dart';
import '../../models/patched_fixture.dart';
import '../theme/app_colors.dart';

/// A quick type filter over the patched rig — what the generator used to
/// offer as its only choice, now a way to tick a whole kind at once.
enum FixtureTypeFilter { all, rgb, moving }

extension FixtureTypeFilterLabel on FixtureTypeFilter {
  String get label => switch (this) {
    FixtureTypeFilter.all => 'All Fixtures',
    FixtureTypeFilter.rgb => 'RGB Only',
    FixtureTypeFilter.moving => 'Moving Heads',
  };

  bool matches(PatchedFixture fixture) => switch (this) {
    FixtureTypeFilter.all => true,
    FixtureTypeFilter.rgb => fixture.profile.category == FixtureCategory.rgb,
    FixtureTypeFilter.moving => fixture.profile.category == FixtureCategory.movingHead,
  };
}

/// Picks individual fixtures: a type filter on top that ticks every fixture
/// of that kind, then one chip per fixture to fine-tune by hand.
class FixtureChecklist extends StatelessWidget {
  final List<PatchedFixture> fixtures;
  final Set<String> selected;
  final FixtureTypeFilter filter;
  final ValueChanged<Set<String>> onChanged;
  final ValueChanged<FixtureTypeFilter> onFilterChanged;

  const FixtureChecklist({
    super.key,
    required this.fixtures,
    required this.selected,
    required this.filter,
    required this.onChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final shown = fixtures.where(filter.matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<FixtureTypeFilter>(
          segments: [
            for (final f in FixtureTypeFilter.values) ButtonSegment(value: f, label: Text(f.label)),
          ],
          selected: {filter},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onFilterChanged(s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${selected.length} of ${fixtures.length} fixtures',
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
            TextButton(
              onPressed: () => onChanged({...selected, for (final f in shown) f.id}),
              child: const Text('All'),
            ),
            TextButton(
              onPressed: () => onChanged(selected.difference({for (final f in shown) f.id})),
              child: const Text('None'),
            ),
          ],
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No patched fixtures of this type', style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final fixture in shown)
                FilterChip(
                  label: Text(fixture.label),
                  selected: selected.contains(fixture.id),
                  onSelected: (on) => onChanged(
                    on ? {...selected, fixture.id} : selected.difference({fixture.id}),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The ids of [filter]'s fixtures — what a type filter ticks when chosen.
Set<String> fixtureIdsOf(List<PatchedFixture> fixtures, FixtureTypeFilter filter) =>
    {for (final f in fixtures) if (filter.matches(f)) f.id};

/// Asks which fixtures something should use, every one ticked to start.
/// Returns null on cancel.
Future<List<PatchedFixture>?> showFixtureSelectDialog(
  BuildContext context, {
  required List<PatchedFixture> fixtures,
  required String title,
}) {
  var filter = FixtureTypeFilter.all;
  var selected = fixtureIdsOf(fixtures, filter);
  return showDialog<List<PatchedFixture>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: FixtureChecklist(
              fixtures: fixtures,
              selected: selected,
              filter: filter,
              onChanged: (s) => setState(() => selected = s),
              onFilterChanged: (f) => setState(() {
                filter = f;
                selected = fixtureIdsOf(fixtures, f);
              }),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(context, [for (final f in fixtures) if (selected.contains(f.id)) f]),
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

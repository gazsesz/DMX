import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_group_style.dart';
import '../../models/fixture_group.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import 'fixture_group_editor_screen.dart';

/// Saved, reusable fixture groups (Front / Back / Moving, …) — set up once
/// here, then reused with one tap from the scene editor instead of
/// re-selecting the same fixtures every time.
class FixtureGroupsScreen extends ConsumerWidget {
  const FixtureGroupsScreen({super.key});

  void _openEditor(BuildContext context, {FixtureGroup? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FixtureGroupEditorScreen(existing: existing)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(fixtureGroupsProvider);
    final patchedIds = ref.watch(patchedFixturesProvider).map((f) => f.id).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: groups.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No saved groups yet.\nBuild one from fixtures you always control together — '
                  '"Front", "Back", "Moving" — and it shows up as a one-tap shortcut in every scene.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint),
                ),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: groups.length,
              onReorder: (oldIndex, newIndex) =>
                  ref.read(fixtureGroupsProvider.notifier).reorder(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final group = groups[index];
                final liveCount = group.fixtureIds.where(patchedIds.contains).length;
                return Card(
                  key: ValueKey(group.id),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: AppColors.panel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: ListTile(
                    onTap: () => _openEditor(context, existing: group),
                    leading: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: fixtureGroupColor(group.iconKey).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(fixtureGroupIcon(group.iconKey), color: fixtureGroupColor(group.iconKey)),
                    ),
                    title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      liveCount == group.fixtureIds.length
                          ? '$liveCount fixtures'
                          : '$liveCount of ${group.fixtureIds.length} fixtures still patched',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fixture-groups-fab',
        onPressed: () => _openEditor(context),
        tooltip: 'New group',
        child: const Icon(Icons.add),
      ),
    );
  }
}

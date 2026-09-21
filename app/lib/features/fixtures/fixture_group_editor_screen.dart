import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../core/widgets/fixture_group_style.dart';
import '../../models/fixture_group.dart';
import '../../models/patched_fixture.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';

/// Create or edit one saved [FixtureGroup] — a name, an icon, and which of
/// the currently patched fixtures belong to it.
class FixtureGroupEditorScreen extends ConsumerStatefulWidget {
  final FixtureGroup? existing;

  const FixtureGroupEditorScreen({super.key, this.existing});

  @override
  ConsumerState<FixtureGroupEditorScreen> createState() => _FixtureGroupEditorScreenState();
}

class _FixtureGroupEditorScreenState extends ConsumerState<FixtureGroupEditorScreen> {
  late final TextEditingController _nameController;
  late String _iconKey;
  late Set<String> _fixtureIds;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _iconKey = widget.existing?.iconKey ?? fixtureGroupIconKeys.first;
    _fixtureIds = {...?widget.existing?.fixtureIds};
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _fixtureIds.isEmpty) return;
    final notifier = ref.read(fixtureGroupsProvider.notifier);
    final existing = widget.existing;
    if (existing != null) {
      notifier.update(
        existing.id,
        (current) => current.copyWith(name: name, iconKey: _iconKey, fixtureIds: _fixtureIds.toList()),
      );
    } else {
      notifier.create(name: name, iconKey: _iconKey, fixtureIds: _fixtureIds.toList());
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text('Delete "${existing.name}"?'),
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
    ref.read(fixtureGroupsProvider.notifier).remove(existing.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allFixtures = ref.watch(patchedFixturesProvider);
    final visible = _query.isEmpty
        ? allFixtures
        : allFixtures.where((f) => f.label.toLowerCase().contains(_query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New group' : 'Edit group'),
        actions: [
          if (widget.existing != null)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: _delete),
          IconButton(icon: const Icon(Icons.check), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: allFixtures.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No patched fixtures yet — patch some in the Fixtures tab first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Front'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ICON',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in fixtureGroupIconKeys)
                      _IconOption(
                        iconKey: key,
                        selected: key == _iconKey,
                        onTap: () => setState(() => _iconKey = key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'FIXTURES',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                    ),
                    const Spacer(),
                    Text(
                      '${_fixtureIds.length} selected',
                      style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search fixtures…',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 4),
                for (final fixture in visible) _FixtureRow(
                  fixture: fixture,
                  selected: _fixtureIds.contains(fixture.id),
                  onChanged: (value) => setState(() {
                    if (value) {
                      _fixtureIds.add(fixture.id);
                    } else {
                      _fixtureIds.remove(fixture.id);
                    }
                  }),
                ),
              ],
            ),
    );
  }
}

class _IconOption extends StatelessWidget {
  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  const _IconOption({required this.iconKey, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = fixtureGroupColor(iconKey);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : AppColors.border, width: 1.5),
          color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: Icon(fixtureGroupIcon(iconKey), color: selected ? color : AppColors.textDim),
      ),
    );
  }
}

class _FixtureRow extends StatelessWidget {
  final PatchedFixture fixture;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _FixtureRow({required this.fixture, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
            Icon(fixtureCategoryIcon(fixture.profile.category), size: 16, color: fixtureCategoryColor(fixture.profile.category)),
            const SizedBox(width: 8),
            Expanded(child: Text(fixture.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
            Text(
              '${fixture.universeId} · ${fixture.startChannel + 1}',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

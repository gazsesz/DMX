import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/fixture_profile.dart';
import '../../models/patched_fixture.dart';
import '../../state/fixture_providers.dart';
import '../../state/artnet_providers.dart';
import 'fixture_editor_screen.dart';
import 'fixture_layout_screen.dart';

IconData _categoryIcon(FixtureCategory category) => fixtureCategoryIcon(category);
Color _categoryColor(FixtureCategory category) => fixtureCategoryColor(category);

class FixturesScreen extends ConsumerStatefulWidget {
  const FixturesScreen({super.key});

  @override
  ConsumerState<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends ConsumerState<FixturesScreen> {
  bool _showPatched = false;

  /// Shared label/universe/start-channel form used both when patching a new
  /// fixture and when editing an already-patched one.
  Future<({String label, String universeId, int startChannel})?> _showPatchFieldsDialog({
    required String title,
    required String confirmLabel,
    required String initialLabel,
    required String initialUniverseId,
    required int initialStartChannel,
  }) async {
    final universes = ref.read(universesProvider);
    final labelController = TextEditingController(text: initialLabel);
    final channelController = TextEditingController(text: initialStartChannel.toString());
    var universeId = initialUniverseId;
    var startChannel = initialStartChannel;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: labelController, decoration: const InputDecoration(labelText: 'Label')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: universeId,
                decoration: const InputDecoration(labelText: 'Universe'),
                items: [
                  for (final u in universes) DropdownMenuItem(value: u.id, child: Text(u.name)),
                ],
                onChanged: (value) => setDialogState(() => universeId = value ?? universeId),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: channelController,
                decoration: const InputDecoration(labelText: 'Start Channel (0-based)'),
                keyboardType: TextInputType.number,
                onChanged: (value) => startChannel = int.tryParse(value) ?? 0,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
          ],
        ),
      ),
    );

    if (result != true) return null;
    return (
      label: labelController.text.trim().isEmpty ? initialLabel : labelController.text.trim(),
      universeId: universeId,
      startChannel: startChannel,
    );
  }

  Future<void> _patch(FixtureProfile profile) async {
    final universes = ref.read(universesProvider);
    if (universes.isEmpty) return;
    final fields = await _showPatchFieldsDialog(
      title: 'Patch: ${profile.name}',
      confirmLabel: 'Patch',
      initialLabel: profile.name,
      initialUniverseId: universes.first.id,
      initialStartChannel: 0,
    );
    if (fields == null) return;
    ref
        .read(patchedFixturesProvider.notifier)
        .patch(
          label: fields.label,
          profile: profile,
          universeId: fields.universeId,
          startChannel: fields.startChannel,
        );
    if (mounted) setState(() => _showPatched = true);
  }

  Future<void> _editPatched(PatchedFixture fixture) async {
    final fields = await _showPatchFieldsDialog(
      title: 'Edit: ${fixture.label}',
      confirmLabel: 'Save',
      initialLabel: fixture.label,
      initialUniverseId: fixture.universeId,
      initialStartChannel: fixture.startChannel,
    );
    if (fields == null) return;
    ref
        .read(patchedFixturesProvider.notifier)
        .update(
          fixture.id,
          (current) => current.copyWith(
            label: fields.label,
            universeId: fields.universeId,
            startChannel: fields.startChannel,
          ),
        );
  }

  Future<void> _createCustom() async {
    final created = await Navigator.of(context).push<FixtureProfile>(
      MaterialPageRoute(builder: (_) => const FixtureEditorScreen()),
    );
    if (created != null && mounted) {
      setState(() => _showPatched = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved "${created.name}" — scroll down to find it in Templates')),
      );
    }
  }

  Future<void> _editCustom(FixtureProfile profile) async {
    final updated = await Navigator.of(context).push<FixtureProfile>(
      MaterialPageRoute(builder: (_) => FixtureEditorScreen(existing: profile)),
    );
    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated "${updated.name}"')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(fixtureLibraryProvider);
    final patched = ref.watch(patchedFixturesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixtures'),
        actions: [
          IconButton(
            tooltip: '2D Stage Layout',
            icon: const Icon(Icons.grid_3x3),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FixtureLayoutScreen()),
            ),
          ),
          const ControlDockAction(), const SaveProjectAction(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Templates')),
                ButtonSegment(value: true, label: Text('Patched (${patched.length})')),
              ],
              selected: {_showPatched},
              onSelectionChanged: (s) => setState(() => _showPatched = s.first),
            ),
          ),
          Expanded(
            child: _showPatched
                ? _PatchedList(fixtures: patched, onEdit: _editPatched)
                : _TemplateGrid(library: library, onPatch: _patch, onEdit: _editCustom),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCustom,
        tooltip: 'Create Custom Fixture',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  final List<FixtureProfile> library;
  final void Function(FixtureProfile) onPatch;
  final void Function(FixtureProfile) onEdit;

  const _TemplateGrid({required this.library, required this.onPatch, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: library.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 138,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final profile = library[index];
        final color = _categoryColor(profile.category);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(7)),
                      child: Icon(_categoryIcon(profile.category), color: color, size: 15),
                    ),
                    const Spacer(),
                    if (!profile.isBuiltIn)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onEdit(profile),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.edit_outlined, size: 14, color: AppColors.textFaint),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  profile.name,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('${profile.channelCount} ch', style: appMonoStyle(fontSize: 9.5, color: AppColors.textFaint)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: OutlinedButton(
                    onPressed: () => onPatch(profile),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('+ Patch', style: TextStyle(fontSize: 10.5)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PatchedList extends ConsumerWidget {
  final List<PatchedFixture> fixtures;
  final void Function(PatchedFixture) onEdit;

  const _PatchedList({required this.fixtures, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fixtures.isEmpty) {
      return const Center(
        child: Text('No fixtures patched yet', style: TextStyle(color: AppColors.textFaint)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: fixtures.length,
      itemBuilder: (context, index) {
        final fixture = fixtures[index];
        final universe = ref.watch(universesProvider).where((u) => u.id == fixture.universeId);
        final universeName = universe.isEmpty ? '?' : universe.first.name;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(_categoryIcon(fixture.profile.category), color: _categoryColor(fixture.profile.category), size: 20),
            title: Text(fixture.label, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${fixture.profile.name} · $universeName · Ch ${fixture.startChannel + 1}-${fixture.startChannel + fixture.profile.channelCount}',
              style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => onEdit(fixture),
                  tooltip: 'Edit label / channel',
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  onPressed: () => ref.read(patchedFixturesProvider.notifier).duplicate(fixture.id),
                  tooltip: 'Duplicate',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: () => ref.read(patchedFixturesProvider.notifier).remove(fixture.id),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

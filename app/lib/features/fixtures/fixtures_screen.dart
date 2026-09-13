import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fixtures/fixture_io.dart';
import '../../core/fixtures/qlcplus_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/fixture_profile.dart';
import '../../models/patched_fixture.dart';
import '../../state/fixture_providers.dart';
import '../../state/artnet_providers.dart';
import 'fixture_editor_screen.dart';
import 'fixture_layout_screen.dart';
import 'fixture_library_browser.dart';

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

  /// Picks a fixture out of the ~1700 that ship with the app.
  Future<void> _addFromLibrary() async {
    final added = await Navigator.of(context).push<FixtureProfile>(
      MaterialPageRoute(builder: (_) => const FixtureLibraryBrowser()),
    );
    if (added == null || !mounted) return;
    setState(() => _showPatched = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${added.name}" — tap it in Templates to patch it'),
      ),
    );
  }

  /// Reads a fixture file the user brought along: this app's own JSON, a
  /// QLC+ `.qxf`, or a CSV channel chart.
  Future<void> _importFixtures() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['qxf', 'json', 'csv', 'xml'],
    );
    final path = file?.path;
    if (path == null || !mounted) return;

    final FixtureImportResult result;
    try {
      final content = await File(path).readAsString();
      result = importFixtures(path.split(RegExp(r'[\\/]')).last, content);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import: $e'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final notifier = ref.read(fixtureLibraryProvider.notifier);
    for (final profile in result.profiles) {
      notifier.addProfile(profile);
    }
    if (!mounted) return;
    setState(() => _showPatched = false);
    final summary = result.profiles.length == 1
        ? 'Imported "${result.profiles.first.name}"'
        : 'Imported ${result.profiles.length} fixtures';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text([summary, ...result.warnings].join('\n')),
        duration: Duration(seconds: result.warnings.isEmpty ? 3 : 6),
      ),
    );
  }

  /// Writes out every fixture the user has added to this project — the
  /// built-in templates aren't theirs to move.
  Future<void> _exportFixtures(String format) async {
    final custom = ref.read(fixtureLibraryProvider).where((f) => !f.isBuiltIn).toList();
    if (custom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No custom fixtures to export yet')),
      );
      return;
    }

    final String content;
    final String extension;
    switch (format) {
      case 'csv':
        content = exportFixturesCsv(custom);
        extension = 'csv';
      case 'qxf':
        // QLC+ definitions are one fixture per file, so exporting several
        // at once would mean several files. Export the first and say so.
        content = writeQxf(custom.first);
        extension = 'qxf';
      default:
        content = exportFixturesJson(custom);
        extension = 'json';
    }

    final name = format == 'qxf' ? custom.first.name : 'fixtures';
    await FilePicker.saveFile(
      dialogTitle: 'Export fixtures',
      fileName: '$name.$extension',
      bytes: Uint8List.fromList(utf8.encode(content)),
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (!mounted) return;
    if (format == 'qxf' && custom.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'QLC+ files hold one fixture each — exported "${custom.first.name}". '
            'Use JSON or CSV to export all ${custom.length} at once.',
          ),
          duration: const Duration(seconds: 6),
        ),
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
          PopupMenuButton<String>(
            tooltip: 'Fixture library, import and export',
            icon: const Icon(Icons.library_books_outlined),
            onSelected: (value) {
              switch (value) {
                case 'library':
                  _addFromLibrary();
                case 'import':
                  _importFixtures();
                default:
                  _exportFixtures(value.substring('export-'.length));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'library', child: Text('Fixture library…')),
              PopupMenuItem(value: 'import', child: Text('Import from file…')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'export-json', child: Text('Export fixtures as JSON…')),
              PopupMenuItem(value: 'export-qxf', child: Text('Export as QLC+ (.qxf)…')),
              PopupMenuItem(value: 'export-csv', child: Text('Export as CSV…')),
            ],
          ),
          const NodeStatusAction(), const ControlDockAction(), const SaveProjectAction(),
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

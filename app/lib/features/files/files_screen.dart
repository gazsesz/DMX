import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/project_snapshot.dart';
import '../../core/storage/project_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/new_project_dialog.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/project_data.dart';
import '../../state/fixture_providers.dart';
import '../../state/project_providers.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  final _storage = ProjectStorage();
  List<ProjectFileInfo> _files = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final files = await _storage.list();
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  ProjectData _snapshot() => buildProjectSnapshot(ref);

  void _applyProject(ProjectData data) => applyProjectData(ref, data);

  Future<void> _save({bool saveAs = false}) async {
    var name = ref.read(currentProjectNameProvider);
    if (saveAs || name.trim().isEmpty) {
      final controller = TextEditingController(text: name);
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Save Project As'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      );
      if (result != true || controller.text.trim().isEmpty) return;
      name = controller.text.trim();
      ref.read(currentProjectNameProvider.notifier).state = name;
    }
    await _storage.save(name, _snapshot());
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
    }
  }

  Future<void> _load(ProjectFileInfo info) async {
    final builtIns = ref.read(fixtureLibraryProvider).where((f) => f.isBuiltIn).toList();
    final data = await _storage.loadFile(info.file, builtIns: builtIns);
    _applyProject(data);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Loaded "${info.name}"')));
    }
  }

  Future<void> _delete(ProjectFileInfo info) async {
    await _storage.delete(info.file);
    await _refresh();
  }

  /// New Project asks what to bring along rather than wiping everything:
  /// re-patching a rig you've already patched is the most expensive way to
  /// start a show, so "keep fixtures" is the default.
  Future<void> _newProject() async {
    final current = ref.read(currentProjectNameProvider);
    final choice = await showNewProjectDialog(
      context,
      title: 'New Project',
      initialName: 'Untitled Project',
      sourceName: current.trim().isEmpty ? 'current show' : current,
    );
    if (choice == null || !mounted) return;
    startProject(ref, name: choice.name, carryOver: choice.carryOver, source: _snapshot());
  }

  /// Copies a saved project under a new name — the same question as New
  /// Project, but sourced from a file instead of what's open.
  Future<void> _duplicate(ProjectFileInfo info) async {
    final builtIns = ref.read(fixtureLibraryProvider).where((f) => f.isBuiltIn).toList();
    final source = await _storage.loadFile(info.file, builtIns: builtIns);
    if (!mounted) return;
    final choice = await showNewProjectDialog(
      context,
      title: 'Duplicate Project',
      initialName: '${info.name} Copy',
      sourceName: info.name,
      initial: ProjectCarryOver.everything,
    );
    if (choice == null || !mounted) return;
    startProject(ref, name: choice.name, carryOver: choice.carryOver, source: source);
    await _storage.save(choice.name, _snapshot());
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created "${choice.name}"')));
    }
  }

  Future<void> _exportToFile() async {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(_snapshot().toJson())),
    );
    final name = ref.read(currentProjectNameProvider);
    await FilePicker.saveFile(
      dialogTitle: 'Export project',
      fileName: '$name.json',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
  }

  Future<void> _importFromFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = file?.path;
    if (path == null) return;
    final builtIns = ref.read(fixtureLibraryProvider).where((f) => f.isBuiltIn).toList();
    final content = await File(path).readAsString();
    final data = ProjectData.fromJson(jsonDecode(content) as Map<String, dynamic>, builtIns: builtIns);
    _applyProject(data);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported "${data.name}"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectName = ref.watch(currentProjectNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'New Project', onPressed: _newProject),
          const NodeStatusAction(), const ControlDockAction(), const SaveProjectAction(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(projectName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: FilledButton(onPressed: () => _save(), child: const Text('Save'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () => _save(saveAs: true), child: const Text('Save As…'))),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'SAVED PROJECTS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No saved projects yet', style: TextStyle(color: AppColors.textFaint)),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final file in _files)
                    ListTile(
                      leading: const Icon(Icons.description_outlined, color: AppColors.accent2),
                      title: Text(file.name),
                      subtitle: Text(
                        '${file.modified.toLocal()}'.split('.').first,
                        style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
                      ),
                      onTap: () => _load(file),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_all_outlined, size: 18),
                            tooltip: 'Duplicate…',
                            onPressed: () => _duplicate(file),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _delete(file),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'IMPORT / EXPORT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importFromFile,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportToFile,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

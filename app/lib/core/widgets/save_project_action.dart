import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/project_snapshot.dart';
import '../../core/storage/project_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../state/project_providers.dart';

/// A "Save Project" app bar action available from every main screen, not
/// just the Files tab — saves the whole show under its current name (or
/// asks for one on the very first save).
class SaveProjectAction extends ConsumerStatefulWidget {
  const SaveProjectAction({super.key});

  @override
  ConsumerState<SaveProjectAction> createState() => _SaveProjectActionState();
}

class _SaveProjectActionState extends ConsumerState<SaveProjectAction> {
  final _storage = ProjectStorage();
  bool _saving = false;

  Future<void> _save() async {
    var name = ref.read(currentProjectNameProvider);
    if (name.trim().isEmpty) {
      final controller = TextEditingController(text: name);
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Save Project'),
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
    setState(() => _saving = true);
    await _storage.save(name, buildProjectSnapshot(ref));
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Save Project',
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined),
      onPressed: _saving ? null : _save,
    );
  }
}

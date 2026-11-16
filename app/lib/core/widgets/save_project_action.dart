import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/autosave_providers.dart';
import '../../state/project_providers.dart';
import '../../l10n/l10n.dart';

/// A "Save Project" app bar action available from every main screen, not
/// just the Files tab — saves the whole show under its current name (or
/// asks for one on the very first save).
class SaveProjectAction extends ConsumerStatefulWidget {
  const SaveProjectAction({super.key});

  @override
  ConsumerState<SaveProjectAction> createState() => _SaveProjectActionState();
}

class _SaveProjectActionState extends ConsumerState<SaveProjectAction> {
  bool _saving = false;

  Future<void> _save() async {
    var name = ref.read(currentProjectNameProvider);
    if (name.trim().isEmpty) {
      final controller = TextEditingController(text: name);
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: Text(context.l10n.wSaveProject),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonSave)),
          ],
        ),
      );
      if (result != true || controller.text.trim().isEmpty) return;
      name = controller.text.trim();
      ref.read(currentProjectNameProvider.notifier).state = name;
    }
    setState(() => _saving = true);
    await ref.read(projectAutoSaveProvider.notifier).saveNow(force: true);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.filesSaved(name))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(projectAutoSaveProvider);
    final busy = _saving || status == ProjectSaveState.saving;
    return IconButton(
      key: const Key('save-project'),
      tooltip: context.l10n.wSaveProject,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          // The dot: edits that aren't on disk yet (an autosave is coming).
          : Badge(
              key: const Key('save-project-dirty'),
              isLabelVisible: status == ProjectSaveState.dirty,
              smallSize: 8,
              backgroundColor: AppColors.accent,
              child: const Icon(Icons.save_outlined),
            ),
      onPressed: _saving ? null : _save,
    );
  }
}

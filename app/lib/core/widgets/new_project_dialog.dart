import 'package:flutter/material.dart';

import '../storage/project_snapshot.dart';
import '../theme/app_colors.dart';

/// What the New Project / Duplicate dialog came back with.
class NewProjectChoice {
  final String name;
  final ProjectCarryOver carryOver;

  const NewProjectChoice({required this.name, required this.carryOver});
}

/// Asks for a name and how much of [sourceName] to bring along.
///
/// Used both for "New Project" (source = the show currently open) and for
/// duplicating a saved file, because they're the same question: patching a
/// rig takes real time, and starting the next show by re-patching the same
/// venue from scratch is the one thing nobody wants to do twice.
Future<NewProjectChoice?> showNewProjectDialog(
  BuildContext context, {
  required String title,
  required String initialName,
  required String sourceName,
  ProjectCarryOver initial = ProjectCarryOver.fixtures,
}) {
  return showDialog<NewProjectChoice>(
    context: context,
    builder: (context) => _NewProjectDialog(
      title: title,
      initialName: initialName,
      sourceName: sourceName,
      initial: initial,
    ),
  );
}

class _NewProjectDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String sourceName;
  final ProjectCarryOver initial;

  const _NewProjectDialog({
    required this.title,
    required this.initialName,
    required this.sourceName,
    required this.initial,
  });

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initialName);
  late ProjectCarryOver _carryOver = widget.initial;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Project name'),
            ),
            const SizedBox(height: 16),
            Text(
              'BRING OVER FROM "${widget.sourceName.toUpperCase()}"',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            for (final option in ProjectCarryOver.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _carryOver = option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: _carryOver == option ? AppColors.panel2 : Colors.transparent,
                      border: Border.all(
                        color: _carryOver == option ? AppColors.accent : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _carryOver == option ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          size: 17,
                          color: _carryOver == option ? AppColors.accent : AppColors.textFaint,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: _carryOver == option ? AppColors.text : AppColors.textDim,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option.description,
                                style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, NewProjectChoice(name: name, carryOver: _carryOver));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

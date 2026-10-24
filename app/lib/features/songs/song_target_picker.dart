import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/smart_program.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';

/// Asks which bank or chase a cue should start. Returns null when dismissed.
Future<ProgramTarget?> showSongTargetPicker(BuildContext context, {String title = 'Start what?'}) {
  return showDialog<ProgramTarget>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 360,
        child: Consumer(
          builder: (context, ref, _) {
            final banks = ref.watch(banksProvider);
            final chases = ref.watch(chasesProvider);
            return ListView(
              shrinkWrap: true,
              children: [
                if (banks.isEmpty && chases.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No banks or chases yet', style: TextStyle(color: AppColors.textFaint)),
                  ),
                if (banks.isNotEmpty) const _Header('BANKS'),
                for (final bank in banks)
                  ListTile(
                    key: ValueKey('target-bank-${bank.id}'),
                    dense: true,
                    leading: Icon(
                      bank.isMovementFx ? Icons.open_with : Icons.grid_view_outlined,
                      size: 18,
                      color: AppColors.accent2,
                    ),
                    title: Text(bank.name, style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.pop(dialogContext, ProgramTarget(id: bank.id, isBank: true)),
                  ),
                if (chases.isNotEmpty) const _Header('CHASES'),
                for (final chase in chases)
                  ListTile(
                    key: ValueKey('target-chase-${chase.id}'),
                    dense: true,
                    leading: const Icon(Icons.fast_forward_outlined, size: 18, color: AppColors.accent),
                    title: Text(chase.name, style: const TextStyle(fontSize: 13)),
                    onTap: () => Navigator.pop(dialogContext, ProgramTarget(id: chase.id, isBank: false)),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
    ),
  );
}

/// The display name of a cue's target, or a marker when it was deleted.
String songTargetName(WidgetRef ref, ProgramTarget? target) {
  if (target == null) return 'Stop';
  if (target.isBank) {
    for (final b in ref.read(banksProvider)) {
      if (b.id == target.id) return b.name;
    }
  } else {
    for (final c in ref.read(chasesProvider)) {
      if (c.id == target.id) return c.name;
    }
  }
  return '(deleted)';
}

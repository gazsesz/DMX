import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bank_providers.dart';
import '../theme/app_colors.dart';

/// Asks the user to pick a bank, with room to spin up a new one or duplicate
/// an existing one without leaving the dialog. Returns the chosen bank's id,
/// or null if dismissed.
Future<String?> showBankPicker(BuildContext context, {String title = 'Assign to Bank'}) {
  return showDialog<String>(
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final bank in banks)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.grid_view_outlined, size: 18, color: AppColors.accent2),
                          title: Text(bank.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${bank.sceneSlots.where((s) => s != null).length}/${bank.sceneSlots.length} slots used',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            tooltip: 'Duplicate this bank',
                            onPressed: () => ref.read(banksProvider.notifier).duplicate(bank.id),
                          ),
                          onTap: () => Navigator.pop(dialogContext, bank.id),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, size: 18, color: AppColors.accent),
                  title: const Text('New Bank', style: TextStyle(fontSize: 13, color: AppColors.accent)),
                  onTap: () {
                    final bank = ref.read(banksProvider.notifier).addBank();
                    Navigator.pop(dialogContext, bank.id);
                  },
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
      ],
    ),
  );
}

/// Drops [sceneId] into the bank's first free slot. Returns a message
/// describing what happened, for the caller to show as a snackbar.
String assignSceneToBank(WidgetRef ref, {required String bankId, required String sceneId}) {
  final banks = ref.read(banksProvider);
  final matches = banks.where((b) => b.id == bankId);
  if (matches.isEmpty) return 'That bank no longer exists';
  final bank = matches.first;
  if (bank.sceneSlots.contains(sceneId)) return 'Already in ${bank.name}';
  final emptyIndex = bank.sceneSlots.indexWhere((slot) => slot == null);
  if (emptyIndex == -1) return '${bank.name} is full';
  ref.read(banksProvider.notifier).setSlot(bankId, emptyIndex, sceneId);
  return 'Added to ${bank.name}, slot ${emptyIndex + 1}';
}

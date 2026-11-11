import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/bank_providers.dart';
import '../theme/app_colors.dart';
import 'duplicate_bank.dart';
import '../../l10n/l10n.dart';

/// Asks the user to pick a bank, with room to spin up a new one or duplicate
/// an existing one without leaving the dialog. Returns the chosen bank's id,
/// or null if dismissed.
Future<String?> showBankPicker(BuildContext context, {String? title}) {
  final dialogTitle = title ?? context.l10n.scAssignToBank;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(dialogTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                      for (final bank in banks.where((b) => !b.isMovementFx))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.grid_view_outlined, size: 18, color: AppColors.accent2),
                          title: Text(bank.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            context.l10n.wSlotsUsed(bank.sceneSlots.where((s) => s != null).length, bank.sceneSlots.length),
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            tooltip: context.l10n.wDuplicateThisBank,
                            onPressed: () => duplicateBankAsking(context, ref, bank),
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
                  title: Text(context.l10n.wNewBank, style: TextStyle(fontSize: 13, color: AppColors.accent)),
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
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.l10n.commonCancel)),
      ],
    ),
  );
}

/// Drops [sceneId] into the bank's first free slot. Returns a message
/// describing what happened, for the caller to show as a snackbar.
String assignSceneToBank(
  WidgetRef ref,
  AppLocalizations l10n, {
  required String bankId,
  required String sceneId,
}) {
  final banks = ref.read(banksProvider);
  final matches = banks.where((b) => b.id == bankId);
  if (matches.isEmpty) return l10n.wThatBankNoLonger;
  final bank = matches.first;
  if (bank.sceneSlots.contains(sceneId)) return l10n.scAlreadyIn(bank.name);
  final emptyIndex = bank.sceneSlots.indexWhere((slot) => slot == null);
  if (emptyIndex == -1) return l10n.scIsFull(bank.name);
  ref.read(banksProvider.notifier).setSlot(bankId, emptyIndex, sceneId);
  return l10n.wAddedToSlot(bank.name, emptyIndex + 1);
}

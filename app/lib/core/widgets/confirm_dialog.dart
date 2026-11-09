import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../../l10n/l10n.dart';

/// Asks before something irreversible. Returns true only on an explicit yes.
///
/// Banks and chases are minutes of work each and there is no undo, so every
/// delete goes through here — a mis-tap on a tablet during a show is not a
/// theoretical risk.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  final deleteLabel = confirmLabel ?? context.l10n.scDelete;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textDim)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(deleteLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// What to do with a bank's scenes when the bank goes.
enum BankDeleteChoice {
  cancel,

  /// Delete the bank, leave its scenes in the project. They simply stop
  /// being in a bank — the Scenes list still has them, unsorted.
  keepScenes,

  /// Delete the bank and the scenes only it was using. Scenes another bank
  /// or a chase still needs are kept regardless; losing those would break
  /// something the user didn't ask about.
  deleteScenes,
}

/// The bank-deletion question, with a straight count of what each answer
/// costs.
Future<BankDeleteChoice> askBankDelete(
  BuildContext context, {
  required String bankName,
  required int sceneCount,
  required int exclusiveSceneCount,
}) async {
  final shared = sceneCount - exclusiveSceneCount;
  final result = await showDialog<BankDeleteChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(context.l10n.wDelete(bankName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sceneCount == 0
                ? context.l10n.wTheBankHasNo
                : context.l10n.confirmBankHoldsScenes(sceneCount),
            style: const TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          if (shared > 0) ...[
            const SizedBox(height: 10),
            Text(
              context.l10n.confirmSharedScenes(shared),
              style: const TextStyle(fontSize: 12, color: AppColors.accent),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, BankDeleteChoice.cancel),
          child: Text(context.l10n.commonCancel),
        ),
        if (exclusiveSceneCount > 0)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, BankDeleteChoice.deleteScenes),
            child: Text(context.l10n.confirmDeleteWithScenes(exclusiveSceneCount)),
          ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, BankDeleteChoice.keepScenes),
          child: Text(sceneCount == 0 ? context.l10n.scDelete : context.l10n.wDeleteKeepScenes),
        ),
      ],
    ),
  );
  return result ?? BankDeleteChoice.cancel;
}

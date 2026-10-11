import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bank.dart';
import '../../state/bank_providers.dart';
import '../../state/scene_providers.dart';
import '../theme/app_colors.dart';

/// Duplicates [bank], first asking whether the copy gets clones of its
/// scenes (the default — editing the copy leaves the original alone) or
/// keeps pointing at the very same scenes. Returns the new bank, or null on
/// cancel.
///
/// A bank with no scenes has nothing to ask about and is copied straight
/// away.
Future<Bank?> duplicateBankAsking(BuildContext context, WidgetRef ref, Bank bank) async {
  final sceneIds = {for (final id in bank.sceneSlots) ?id};
  var clone = true;
  if (sceneIds.isNotEmpty) {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: Text('Duplicate "${bank.name}"'),
          content: RadioGroup<bool>(
            groupValue: clone,
            onChanged: (v) => setDialogState(() => clone = v ?? clone),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: const Text('Clone the scenes'),
                  subtitle: Text(
                    '${sceneIds.length} new scene(s) — editing the copy leaves the original alone',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                  ),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: const Text('Use the same scenes'),
                  subtitle: const Text(
                    'Both banks share them — a change shows up in both',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, clone), child: const Text('Duplicate')),
          ],
        ),
      ),
    );
    if (answer == null) return null;
    clone = answer;
  }

  Map<String, String>? sceneMap;
  if (clone && sceneIds.isNotEmpty) {
    // One clone per scene, so a scene used in two slots stays one scene in
    // the copy too.
    final scenes = ref.read(scenesProvider.notifier);
    sceneMap = {};
    for (final id in sceneIds) {
      final copy = scenes.duplicate(id);
      if (copy != null) sceneMap[id] = copy.id;
    }
  }
  return ref.read(banksProvider.notifier).duplicate(bank.id, sceneMap: sceneMap);
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/project_providers.dart';
import '../../state/scene_providers.dart';
import '../storage/show_items_io.dart';
import '../theme/app_colors.dart';

const _uuid = Uuid();

/// Writes [bankIds] and/or [chaseIds] — with every scene they play — to a
/// file the user picks. See [ShowItemsExport].
Future<void> exportShowItemsToFile(
  BuildContext context,
  WidgetRef ref, {
  Iterable<String> bankIds = const [],
  Iterable<String> chaseIds = const [],
}) async {
  final export = ShowItemsExport.collect(
    projectName: ref.read(currentProjectNameProvider),
    bankIds: bankIds,
    chaseIds: chaseIds,
    allBanks: ref.read(banksProvider),
    allChases: ref.read(chasesProvider),
    allScenes: ref.read(scenesProvider),
    allFixtures: ref.read(patchedFixturesProvider),
    allLayers: ref.read(layersProvider),
  );
  final messenger = ScaffoldMessenger.of(context);
  final path = await FilePicker.saveFile(
    dialogTitle: 'Export',
    fileName: export.suggestedFileName,
    bytes: Uint8List.fromList(utf8.encode(export.encode())),
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return;
  final what = [
    if (export.banks.isNotEmpty) '${export.banks.length} bank${export.banks.length == 1 ? '' : 's'}',
    if (export.chases.isNotEmpty) '${export.chases.length} chase${export.chases.length == 1 ? '' : 's'}',
    '${export.scenes.length} scene${export.scenes.length == 1 ? '' : 's'}',
  ].join(', ');
  messenger.showSnackBar(SnackBar(content: Text('Exported $what')));
}

/// Reads a bank/chase export the user picks and adds its contents to the
/// project. Returns what was added (null when cancelled or unreadable).
Future<ShowItemsImport?> importShowItemsFromFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  final path = file?.path;
  if (path == null) return null;

  final ShowItemsImport result;
  try {
    result = importShowItems(
      await File(path).readAsString(),
      fixtures: ref.read(patchedFixturesProvider),
      layers: ref.read(layersProvider),
      bankNames: {for (final b in ref.read(banksProvider)) b.name},
      chaseNames: {for (final c in ref.read(chasesProvider)) c.name},
      sceneNames: {for (final s in ref.read(scenesProvider)) s.name},
      newId: _uuid.v4,
    );
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not import: ${e.message}'), backgroundColor: AppColors.danger));
    return null;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not import: $e'), backgroundColor: AppColors.danger));
    return null;
  }

  ref.read(scenesProvider.notifier).loadAll([...ref.read(scenesProvider), ...result.scenes]);
  ref.read(banksProvider.notifier).loadAll([...ref.read(banksProvider), ...result.banks]);
  ref.read(chasesProvider.notifier).loadAll([...ref.read(chasesProvider), ...result.chases]);
  messenger.showSnackBar(
    SnackBar(
      content: Text([result.summary, ...result.warnings].join('\n')),
      duration: Duration(seconds: result.warnings.isEmpty ? 3 : 8),
    ),
  );
  return result;
}

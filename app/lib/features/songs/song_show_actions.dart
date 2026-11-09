import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/song_show_io.dart';
import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/project_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/song_show_providers.dart';
import '../../l10n/l10n.dart';

const _uuid = Uuid();

/// Writes [show] — with the banks, chases and fixture groups it needs, but not
/// the song — to a file the user picks.
Future<void> exportSongShowToFile(BuildContext context, WidgetRef ref, SongShow show) async {
  final export = SongShowExport.collect(
    projectName: ref.read(currentProjectNameProvider),
    show: show,
    allBanks: ref.read(banksProvider),
    allChases: ref.read(chasesProvider),
    allScenes: ref.read(scenesProvider),
    allFixtures: ref.read(patchedFixturesProvider),
    allLayers: ref.read(layersProvider),
    allGroups: ref.read(fixtureGroupsProvider),
  );
  final messenger = ScaffoldMessenger.of(context);
  final path = await FilePicker.saveFile(
    dialogTitle: context.l10n.songExportSongShow,
    fileName: export.suggestedFileName,
    bytes: Uint8List.fromList(utf8.encode(export.encode())),
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (path == null) return;
  final audioNote = show.audio == null ? '' : context.l10n.songTheSongFileIs;
  messenger.showSnackBar(SnackBar(content: Text(context.l10n.songExported(show.name, audioNote)), duration: const Duration(seconds: 6)));
}

/// Reads a song show export the user picks and adds it to the project.
/// Returns the new show (null when cancelled or unreadable).
Future<SongShow?> importSongShowFromFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  final path = file?.path;
  if (path == null) return null;

  final SongShowImport result;
  try {
    result = importSongShow(
      await File(path).readAsString(),
      fixtures: ref.read(patchedFixturesProvider),
      layers: ref.read(layersProvider),
      groups: ref.read(fixtureGroupsProvider),
      banks: ref.read(banksProvider),
      chases: ref.read(chasesProvider),
      sceneNames: {for (final s in ref.read(scenesProvider)) s.name},
      sceneIds: {for (final s in ref.read(scenesProvider)) s.id},
      songShowNames: {for (final s in ref.read(songShowsProvider)) s.name},
      newId: _uuid.v4,
    );
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.wCouldNotImport(e.message)), backgroundColor: AppColors.danger));
    return null;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.scCouldNotImport(e)), backgroundColor: AppColors.danger));
    return null;
  }

  applySongShowImport(ref, result);
  messenger.showSnackBar(
    SnackBar(
      content: Text([
        result.summary,
        if (result.needsAudio && result.show.audio != null) 'Open it and link "${result.show.audio!.fileName}" to play it.',
        ...result.warnings,
      ].join('\n')),
      duration: const Duration(seconds: 9),
    ),
  );
  return result.show;
}

/// Adds everything [result] brings to the project's lists.
void applySongShowImport(WidgetRef ref, SongShowImport result) {
  final items = result.items;
  if (items != null) {
    ref.read(scenesProvider.notifier).loadAll([...ref.read(scenesProvider), ...items.scenes]);
    ref.read(banksProvider.notifier).loadAll([...ref.read(banksProvider), ...items.banks]);
    ref.read(chasesProvider.notifier).loadAll([...ref.read(chasesProvider), ...items.chases]);
  }
  if (result.newGroups.isNotEmpty) {
    ref.read(fixtureGroupsProvider.notifier).loadAll([...ref.read(fixtureGroupsProvider), ...result.newGroups]);
  }
  ref.read(songShowsProvider.notifier).upsert(result.show);
}

import 'dart:convert';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/fixture_group.dart';
import '../../models/layer.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';
import 'show_items_io.dart';

/// A song show on its own, to move between projects or machines.
///
/// The file carries the timeline plus everything its cues start (banks,
/// chases, the scenes they play, the fixtures those scenes touch) and the
/// fixture groups the show is limited to — all described the way
/// `show_items_io.dart` describes them, so an import lands them on the rig it
/// is opened in. The song itself is **not** in the file, only its name and
/// length: the importing side links its own copy of the audio.
const songShowFormat = 'smartdmx-song-show';
const songShowFormatVersion = 1;

class SongShowExport {
  final SongShow show;
  final ShowItemsExport items;
  final List<FixtureGroup> groups;

  /// The layers the cues name, so an import can find them by name.
  final List<Layer> cueLayers;

  /// Fixtures the groups hold, described for matching on import.
  final List<ExportedFixture> groupFixtures;

  const SongShowExport({
    required this.show,
    required this.items,
    required this.groups,
    required this.cueLayers,
    required this.groupFixtures,
  });

  factory SongShowExport.collect({
    required String projectName,
    required SongShow show,
    required List<Bank> allBanks,
    required List<Chase> allChases,
    required List<Scene> allScenes,
    required List<PatchedFixture> allFixtures,
    required List<Layer> allLayers,
    required List<FixtureGroup> allGroups,
  }) {
    final items = ShowItemsExport.collect(
      projectName: projectName,
      bankIds: {for (final c in show.cues) ?c.target?.bankId},
      chaseIds: {for (final c in show.cues) ?c.target?.chaseId},
      sceneIds: {for (final c in show.cues) ?c.sceneId},
      allBanks: allBanks,
      allChases: allChases,
      allScenes: allScenes,
      allFixtures: allFixtures,
      allLayers: allLayers,
    );
    final groups = [for (final g in allGroups) if (show.groupIds.contains(g.id)) g];
    final groupFixtureIds = {for (final g in groups) ...g.fixtureIds};
    final cueLayerIds = {for (final c in show.cues) c.layerId};
    return SongShowExport(
      show: show,
      items: items,
      groups: groups,
      cueLayers: [for (final l in allLayers) if (cueLayerIds.contains(l.id)) l],
      groupFixtures: [
        for (final f in allFixtures)
          if (groupFixtureIds.contains(f.id)) ExportedFixture.of(f),
      ],
    );
  }

  String get suggestedFileName {
    final safe = show.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${safe.isEmpty ? 'song show' : safe}.smartshow.json';
  }

  String encode() {
    final base = jsonDecode(items.encode()) as Map<String, dynamic>;
    final fixtures = <String, dynamic>{
      for (final f in base['fixtures'] as List) (f as Map<String, dynamic>)['id'] as String: f,
      for (final f in groupFixtures) f.id: f.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert({
      ...base,
      'format': songShowFormat,
      'formatVersion': songShowFormatVersion,
      'fixtures': fixtures.values.toList(),
      'songShow': {
        ...show.toJson(),
        // Where the song is on this machine means nothing on another.
        if (show.audio != null) 'audio': show.audio!.toJson(withPath: false),
      },
      'groups': [for (final g in groups) g.toJson()],
      'cueLayers': [for (final l in cueLayers) l.toJson()],
    });
  }
}

/// What importing a song show adds, and what it couldn't bring over.
class SongShowImport {
  /// The show, ready to add: new id, cues re-pointed at the project's (or the
  /// freshly imported) banks and chases, layers and groups.
  final SongShow show;

  /// Banks, chases and scenes to add; null when the project already had every
  /// one of them (a round trip within one project).
  final ShowItemsImport? items;

  /// Groups that didn't exist here and are created from the file.
  final List<FixtureGroup> newGroups;
  final List<String> warnings;

  const SongShowImport({required this.show, required this.items, required this.newGroups, required this.warnings});

  bool get needsAudio => show.audio?.path == null;

  String get summary {
    final parts = [
      '"${show.name}"',
      if (items != null) '${items!.banks.length + items!.chases.length} banks/chases',
      if (newGroups.isNotEmpty) '${newGroups.length} group${newGroups.length == 1 ? '' : 's'}',
    ];
    return 'Imported ${parts.join(', ')}';
  }
}

/// Reads a file made by [SongShowExport.encode] into a show for a project
/// with the given contents. Throws [FormatException] with a readable message
/// for anything that isn't one.
SongShowImport importSongShow(
  String content, {
  required List<PatchedFixture> fixtures,
  required List<Layer> layers,
  required List<FixtureGroup> groups,
  required List<Bank> banks,
  required List<Chase> chases,
  required Set<String> sceneNames,
  required Set<String> sceneIds,
  required Set<String> songShowNames,
  required String Function() newId,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    throw const FormatException('This file isn\'t valid JSON.');
  }
  if (decoded is! Map<String, dynamic> || decoded['format'] != songShowFormat || decoded['songShow'] is! Map) {
    throw const FormatException('This isn\'t a song show export.');
  }
  if (((decoded['formatVersion'] as num?)?.toInt() ?? 0) > songShowFormatVersion) {
    throw const FormatException('This export was made by a newer version of the app — update to import it.');
  }
  final json = decoded;
  final source = SongShow.fromJson(Map<String, dynamic>.from(json['songShow'] as Map));
  final warnings = <String>[];

  // Banks and chases: a file from this very project finds all of them again by
  // id and adds nothing; otherwise everything in it comes in as new copies.
  final fileBankIds = {for (final b in json['banks'] as List? ?? const []) (b as Map)['id'] as String};
  final fileChaseIds = {for (final c in json['chases'] as List? ?? const []) (c as Map)['id'] as String};
  final haveBanks = {for (final b in banks) b.id};
  final haveChases = {for (final c in chases) c.id};
  final cueSceneIds = {for (final c in source.cues) ?c.sceneId};
  final everythingHere = fileBankIds.every(haveBanks.contains) &&
      fileChaseIds.every(haveChases.contains) &&
      cueSceneIds.every(sceneIds.contains);

  ShowItemsImport? items;
  var bankMap = <String, String>{};
  var chaseMap = <String, String>{};
  var sceneMap = <String, String>{};
  if (everythingHere) {
    bankMap = {for (final id in fileBankIds) id: id};
    chaseMap = {for (final id in fileChaseIds) id: id};
    sceneMap = {for (final id in cueSceneIds) id: id};
  } else {
    items = importShowItems(
      content,
      fixtures: fixtures,
      layers: layers,
      bankNames: {for (final b in banks) b.name},
      chaseNames: {for (final c in chases) c.name},
      sceneNames: sceneNames,
      newId: newId,
      format: songShowFormat,
    );
    bankMap = items.bankIdMap;
    chaseMap = items.chaseIdMap;
    sceneMap = items.sceneIdMap;
    warnings.addAll(items.warnings);
  }

  // Layers the cues play on: same id, else same name, else Layer 1.
  final layerMap = <String, String>{};
  for (final layer in (json['cueLayers'] as List? ?? const []).map((l) => Layer.fromJson(l as Map<String, dynamic>))) {
    final match = layers.where((l) => l.id == layer.id).firstOrNull ??
        layers.where((l) => l.name.trim().toLowerCase() == layer.name.trim().toLowerCase()).firstOrNull;
    if (match == null) {
      warnings.add('Layer "${layer.name}" doesn\'t exist here — its cues play on Layer 1.');
    }
    layerMap[layer.id] = match?.id ?? layer1Id;
  }

  var dropped = 0;
  final cues = <SongCue>[];
  for (final cue in source.cues) {
    final target = cue.target;
    ProgramTarget? mapped;
    if (target != null) {
      final newTarget = target.isBank ? bankMap[target.id] : chaseMap[target.id];
      if (newTarget == null) {
        dropped++;
        continue;
      }
      mapped = ProgramTarget(id: newTarget, isBank: target.isBank, lane: target.lane);
    }
    String? mappedScene;
    if (cue.sceneId != null) {
      mappedScene = sceneMap[cue.sceneId];
      if (mappedScene == null) {
        dropped++;
        continue;
      }
    }
    cues.add(SongCue(
      id: newId(),
      atBeat: cue.atBeat,
      layerId: layerMap[cue.layerId] ?? layer1Id,
      action: cue.action,
      target: mapped,
      sceneId: mappedScene,
    ));
  }
  if (dropped > 0) warnings.add('$dropped cue${dropped == 1 ? '' : 's'} pointed at something missing from the file and were left out.');

  // Fixture groups: same id, else same name, else rebuilt from the fixtures
  // that exist here.
  final fixtureMatch = matchExportedFixtures(
    (json['fixtures'] as List? ?? const []).map((f) => ExportedFixture.fromJson(f as Map<String, dynamic>)),
    fixtures,
  ).map;
  final groupIds = <String>[];
  final newGroups = <FixtureGroup>[];
  for (final group in (json['groups'] as List? ?? const []).map((g) => FixtureGroup.fromJson(g as Map<String, dynamic>))) {
    final existing = groups.where((g) => g.id == group.id).firstOrNull ??
        groups.where((g) => g.name.trim().toLowerCase() == group.name.trim().toLowerCase()).firstOrNull;
    if (existing != null) {
      groupIds.add(existing.id);
      continue;
    }
    final members = [for (final id in group.fixtureIds) ?fixtureMatch[id]];
    if (members.isEmpty) {
      warnings.add('Group "${group.name}" has no matching fixtures here — the show plays on every fixture instead.');
      continue;
    }
    final created = group.copyWith(fixtureIds: members);
    final fresh = FixtureGroup(id: newId(), name: created.name, iconKey: created.iconKey, fixtureIds: members);
    newGroups.add(fresh);
    groupIds.add(fresh.id);
    if (members.length < group.fixtureIds.length) {
      warnings.add('Group "${group.name}" is missing ${group.fixtureIds.length - members.length} fixture(s) here.');
    }
  }

  var name = source.name;
  if (songShowNames.contains(name)) {
    name = '${source.name} (imported)';
    for (var n = 2; songShowNames.contains(name); n++) {
      name = '${source.name} (imported $n)';
    }
  }

  final audio = source.audio;
  return SongShowImport(
    show: SongShow(
      id: newId(),
      name: name,
      origin: source.origin,
      audio: audio == null ? null : SongAudioRef(fileName: audio.fileName, durationMs: audio.durationMs, sha1: audio.sha1),
      bpm: source.bpm,
      beatOffsetMs: source.beatOffsetMs,
      sections: source.sections,
      cues: cues,
      groupIds: groupIds,
    ),
    items: items,
    newGroups: newGroups,
    warnings: warnings,
  );
}

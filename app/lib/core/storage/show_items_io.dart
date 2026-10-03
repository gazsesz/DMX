import 'dart:convert';

import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/group_position.dart';
import '../../models/layer.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';

/// Moving banks and chases (with the scenes they play) between projects, or
/// between two copies of the app.
///
/// A scene stores values against patched-fixture ids, which only mean
/// something inside the project that patched them. So an export also
/// describes every fixture its scenes touch (name, model, where it's
/// patched), and an import maps each one onto the rig it lands in: the same
/// fixture if it's the same project, otherwise one with the same name, or
/// failing that the same universe and start address — always with the same
/// channel count. Anything left unmatched is left out and reported, rather
/// than being written onto the wrong lamp.
///
/// Everything imported gets fresh ids, so importing never overwrites what's
/// already in the project; it only ever adds.

const showItemsFormat = 'smartdmx-show-items';
const showItemsFormatVersion = 1;

/// What an export carries about one patched fixture, to find it again.
class ExportedFixture {
  final String id;
  final String label;
  final String profileName;
  final int channelCount;
  final String universeId;
  final int startChannel;

  const ExportedFixture({
    required this.id,
    required this.label,
    required this.profileName,
    required this.channelCount,
    required this.universeId,
    required this.startChannel,
  });

  factory ExportedFixture.of(PatchedFixture f) => ExportedFixture(
    id: f.id,
    label: f.label,
    profileName: f.profile.qualifiedName,
    channelCount: f.profile.channelCount,
    universeId: f.universeId,
    startChannel: f.startChannel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'profile': profileName,
    'channels': channelCount,
    'universeId': universeId,
    'startChannel': startChannel,
  };

  factory ExportedFixture.fromJson(Map<String, dynamic> json) => ExportedFixture(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    profileName: json['profile'] as String? ?? '',
    channelCount: (json['channels'] as num?)?.toInt() ?? 0,
    universeId: json['universeId'] as String? ?? '',
    startChannel: (json['startChannel'] as num?)?.toInt() ?? -1,
  );
}

/// The banks and/or chases to write out, plus everything they need.
class ShowItemsExport {
  final String projectName;
  final List<Bank> banks;
  final List<Chase> chases;
  final List<Scene> scenes;
  final List<ExportedFixture> fixtures;
  final List<Layer> layers;

  const ShowItemsExport({
    required this.projectName,
    required this.banks,
    required this.chases,
    required this.scenes,
    required this.fixtures,
    required this.layers,
  });

  /// Gathers [bankIds] and [chaseIds] from a project: the banks a chase
  /// steps through come along with it, and every scene any of them plays.
  factory ShowItemsExport.collect({
    required String projectName,
    Iterable<String> bankIds = const [],
    Iterable<String> chaseIds = const [],
    required List<Bank> allBanks,
    required List<Chase> allChases,
    required List<Scene> allScenes,
    required List<PatchedFixture> allFixtures,
    required List<Layer> allLayers,
  }) {
    final chases = allChases.where((c) => chaseIds.contains(c.id)).toList();
    final wantedBanks = {...bankIds, for (final c in chases) for (final s in c.steps) ?s.bankId};
    final banks = allBanks.where((b) => wantedBanks.contains(b.id)).toList();
    final wantedScenes = {
      for (final b in banks) for (final id in b.sceneSlots) ?id,
      for (final c in chases) for (final s in c.steps) ?s.sceneId,
    };
    final scenes = allScenes.where((s) => wantedScenes.contains(s.id)).toList();
    final fixtureIds = {for (final s in scenes) ...s.fixtureValues.keys};
    final layerIds = {for (final c in chases) for (final s in c.steps) ?s.layerId};
    return ShowItemsExport(
      projectName: projectName,
      banks: banks,
      chases: chases,
      scenes: scenes,
      fixtures: [for (final f in allFixtures) if (fixtureIds.contains(f.id)) ExportedFixture.of(f)],
      layers: allLayers.where((l) => layerIds.contains(l.id)).toList(),
    );
  }

  /// A file name for the export: the one item's name, or the project's.
  String get suggestedFileName {
    final single = banks.length + chases.length == 1;
    final base = !single ? projectName : (chases.isNotEmpty ? chases.first.name : banks.first.name);
    final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${safe.isEmpty ? 'show' : safe}.dmxitems.json';
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': showItemsFormat,
    'formatVersion': showItemsFormatVersion,
    'exportedFrom': projectName,
    'fixtures': [for (final f in fixtures) f.toJson()],
    'layers': [for (final l in layers) l.toJson()],
    'scenes': [for (final s in scenes) s.toJson()],
    'banks': [for (final b in banks) b.toJson()],
    'chases': [for (final c in chases) c.toJson()],
  });
}

/// What an import adds to the project, and what it couldn't bring over.
class ShowItemsImport {
  final List<Scene> scenes;
  final List<Bank> banks;
  final List<Chase> chases;
  final List<String> warnings;

  const ShowItemsImport({required this.scenes, required this.banks, required this.chases, required this.warnings});

  String get summary {
    final parts = [
      if (banks.isNotEmpty) '${banks.length} bank${banks.length == 1 ? '' : 's'}',
      if (chases.isNotEmpty) '${chases.length} chase${chases.length == 1 ? '' : 's'}',
      '${scenes.length} scene${scenes.length == 1 ? '' : 's'}',
    ];
    return 'Imported ${parts.join(', ')}';
  }
}

/// Reads an export made by [ShowItemsExport.encode] into new items for a
/// project with [fixtures], [layers] and the names already in use.
///
/// [newId] mints ids (a uuid in the app; predictable in tests). Throws
/// [FormatException] with a message worth showing for a file that isn't
/// one of these exports.
ShowItemsImport importShowItems(
  String content, {
  required List<PatchedFixture> fixtures,
  required List<Layer> layers,
  required Set<String> bankNames,
  required Set<String> chaseNames,
  required Set<String> sceneNames,
  required String Function() newId,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    throw const FormatException('This file isn\'t valid JSON.');
  }
  if (decoded is! Map<String, dynamic> || decoded['format'] != showItemsFormat) {
    throw const FormatException('This isn\'t a bank/chase export. Whole projects are opened from the Files tab.');
  }
  final version = (decoded['formatVersion'] as num?)?.toInt() ?? 0;
  if (version > showItemsFormatVersion) {
    throw const FormatException('This export was made by a newer version of the app — update to import it.');
  }

  final json = decoded;
  List<Map<String, dynamic>> list(String key) => [
    for (final item in json[key] as List? ?? const []) item as Map<String, dynamic>,
  ];

  final warnings = <String>[];

  // Fixtures: same id, else same name, else same address — same size always.
  final fixtureMap = <String, String>{};
  final unmatched = <String>[];
  for (final exported in list('fixtures').map(ExportedFixture.fromJson)) {
    bool fits(PatchedFixture f) => f.profile.channelCount == exported.channelCount;
    final match = fixtures.where((f) => f.id == exported.id && fits(f)).firstOrNull ??
        fixtures.where((f) => f.label.trim().toLowerCase() == exported.label.trim().toLowerCase() && fits(f)).firstOrNull ??
        fixtures
            .where((f) => f.universeId == exported.universeId && f.startChannel == exported.startChannel && fits(f))
            .firstOrNull;
    if (match == null) {
      unmatched.add(exported.label);
    } else {
      fixtureMap[exported.id] = match.id;
    }
  }
  if (unmatched.isNotEmpty) {
    warnings.add(
      'Not in this rig, so left out of the scenes: ${unmatched.join(', ')}. '
      'Patch a fixture with the same name and channel count, then import again.',
    );
  }

  // Layers: same id, else same name, else Layer 1.
  final layerMap = <String, String?>{};
  for (final layer in list('layers').map(Layer.fromJson)) {
    final match = layers.where((l) => l.id == layer.id).firstOrNull ??
        layers.where((l) => l.name.trim().toLowerCase() == layer.name.trim().toLowerCase()).firstOrNull;
    layerMap[layer.id] = match?.id;
    if (match == null) warnings.add('Layer "${layer.name}" doesn\'t exist here — its chase steps play on Layer 1.');
  }

  String uniqueName(String name, Set<String> taken) {
    if (!taken.contains(name)) {
      taken.add(name);
      return name;
    }
    var candidate = '$name (imported)';
    for (var n = 2; taken.contains(candidate); n++) {
      candidate = '$name (imported $n)';
    }
    taken.add(candidate);
    return candidate;
  }

  final sceneMap = <String, String>{};
  final scenes = <Scene>[];
  for (final source in list('scenes').map(Scene.fromJson)) {
    final id = newId();
    sceneMap[source.id] = id;
    String? mapFixture(String old) => fixtureMap[old];
    final groups = source.fixtureGroups;
    final positions = source.groupPositions;
    // Groups and their position settings are kept index-aligned; a group
    // that lost every fixture goes, and its position settings with it.
    final keptGroups = <List<String>>[];
    final keptPositions = <GroupPosition?>[];
    if (groups != null) {
      for (var g = 0; g < groups.length; g++) {
        final ids = [for (final old in groups[g]) ?mapFixture(old)];
        if (ids.isEmpty) continue;
        keptGroups.add(ids);
        final position = positions != null && g < positions.length ? positions[g] : null;
        keptPositions.add(position == null ? null : _remapPosition(position, fixtureMap));
      }
    }
    scenes.add(Scene(
      id: id,
      name: uniqueName(source.name, sceneNames),
      fixtureValues: {
        for (final entry in source.fixtureValues.entries)
          ?mapFixture(entry.key): entry.value,
      },
      fixtureGroups: groups == null ? null : keptGroups,
      groupPositions: positions == null ? null : keptPositions,
    ));
  }

  final bankMap = <String, String>{};
  final banks = <Bank>[];
  for (final source in list('banks').map(Bank.fromJson)) {
    final id = newId();
    bankMap[source.id] = id;
    banks.add(Bank(
      id: id,
      name: uniqueName(source.name, bankNames),
      sceneSlots: [for (final slot in source.sceneSlots) slot == null ? null : sceneMap[slot]],
      isBeatFlash: source.isBeatFlash,
      flashFadeOutMs: source.flashFadeOutMs,
      ownTiming: source.ownTiming,
      holdMs: source.holdMs,
      fadeMs: source.fadeMs,
      slotTimings: source.slotTimings,
    ));
  }

  final chases = <Chase>[];
  for (final source in list('chases').map(Chase.fromJson)) {
    chases.add(Chase(
      id: newId(),
      name: uniqueName(source.name, chaseNames),
      stepSeconds: source.stepSeconds,
      beatSync: source.beatSync,
      direction: source.direction,
      laneTimings: source.laneTimings,
      steps: [
        for (final step in source.steps)
          if ((step.sceneId == null || sceneMap.containsKey(step.sceneId)) &&
              (step.bankId == null || bankMap.containsKey(step.bankId)))
            ChaseStep(
              sceneId: step.sceneId == null ? null : sceneMap[step.sceneId],
              bankId: step.bankId == null ? null : bankMap[step.bankId],
              hold: step.hold,
              fade: step.fade,
              layerId: step.layerId == null ? null : layerMap[step.layerId],
            ),
      ],
    ));
  }

  if (scenes.isEmpty && banks.isEmpty && chases.isEmpty) {
    throw const FormatException('The file holds no banks, chases or scenes.');
  }
  return ShowItemsImport(scenes: scenes, banks: banks, chases: chases, warnings: warnings);
}

GroupPosition _remapPosition(GroupPosition position, Map<String, String> fixtureMap) {
  return position.copyWith(
    manual: {
      for (final e in position.manual.entries)
        ?fixtureMap[e.key]: e.value,
    },
    aimOverrides: {
      for (final e in position.aimOverrides.entries)
        ?fixtureMap[e.key]: e.value,
    },
  );
}

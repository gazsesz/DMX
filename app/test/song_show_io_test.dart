import 'dart:convert';

import 'package:dmx_controller/core/storage/show_items_io.dart';
import 'package:dmx_controller/core/storage/song_show_io.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final par = FixtureProfile(
    id: 'par',
    name: 'PAR',
    category: FixtureCategory.rgb,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
    ],
  );
  List<PatchedFixture> rig() => [
    for (var i = 0; i < 3; i++)
      PatchedFixture(id: 'f$i', label: 'Par ${i + 1}', profile: par, universeId: 'u1', startChannel: i * 2),
  ];

  const scene = Scene(id: 'sc1', name: 'Red', fixtureValues: {
    'f0': {1: 255},
    'f1': {1: 255},
  });
  const bank = Bank(id: 'b1', name: 'Looks', sceneSlots: ['sc1']);
  const chase = Chase(id: 'ch1', name: 'Run', steps: [ChaseStep(bankId: 'b1')]);
  const layers = [
    Layer(id: layer1Id, name: 'Layer 1', priority: 1),
    Layer(id: layer2Id, name: 'Layer 2', priority: 2),
  ];
  const group = FixtureGroup(id: 'g1', name: 'Front', iconKey: 'all', fixtureIds: ['f0', 'f1']);

  const show = SongShow(
    id: 'show1',
    name: 'Opener',
    bpm: 126,
    beatOffsetMs: 40,
    audio: SongAudioRef(fileName: 'opener.mp3', durationMs: 200000, path: '/secret/place/opener.mp3'),
    sections: [SongSection(startBeat: 0, lengthBeats: 32, kind: SongSectionKind.intro)],
    groupIds: ['g1'],
    cues: [
      SongCue(id: 'c1', atBeat: 0, layerId: layer1Id, target: ProgramTarget(id: 'b1', isBank: true)),
      SongCue(id: 'c2', atBeat: 16, layerId: layer2Id, target: ProgramTarget(id: 'ch1', isBank: false)),
      SongCue(id: 'c3', atBeat: 32, layerId: layer2Id, action: SongCueAction.stop),
    ],
  );

  String export() => SongShowExport.collect(
    projectName: 'Club',
    show: show,
    allBanks: const [bank],
    allChases: const [chase],
    allScenes: const [scene],
    allFixtures: rig(),
    allLayers: layers,
    allGroups: const [group],
  ).encode();

  var counter = 0;
  String newId() => 'new${counter++}';

  SongShowImport import(
    String content, {
    List<PatchedFixture>? fixtures,
    List<Layer> inLayers = layers,
    List<FixtureGroup> groups = const [],
    List<Bank> banks = const [],
    List<Chase> chases = const [],
    Set<String> names = const {},
    Set<String> sceneIds = const {},
  }) {
    counter = 0;
    return importSongShow(
      content,
      fixtures: fixtures ?? rig(),
      layers: inLayers,
      groups: groups,
      banks: banks,
      chases: chases,
      sceneNames: {},
      sceneIds: sceneIds,
      songShowNames: {...names},
      newId: newId,
    );
  }

  test('the file names the song but never says where it is on this machine', () {
    final json = jsonDecode(export()) as Map<String, dynamic>;
    expect(json['format'], songShowFormat);
    final audio = (json['songShow'] as Map)['audio'] as Map;
    expect(audio['fileName'], 'opener.mp3');
    expect(audio.containsKey('path'), isFalse);
    expect(export().contains('secret'), isFalse);
  });

  test('into an empty project: banks and chases come in as copies and the cues follow them', () {
    final result = import(export());
    expect(result.items, isNotNull);
    expect(result.items!.banks, hasLength(1));
    expect(result.items!.chases, hasLength(1));
    expect(result.items!.scenes, hasLength(1));
    final newBank = result.items!.banks.single.id;
    final newChase = result.items!.chases.single.id;
    expect(newBank, isNot('b1'));
    final cues = result.show.cues;
    expect(cues[0].target!.bankId, newBank);
    expect(cues[1].target!.chaseId, newChase);
    expect(cues[2].action, SongCueAction.stop);
    expect(cues.map((c) => c.layerId), [layer1Id, layer2Id, layer2Id]);
    expect(result.show.bpm, 126);
    expect(result.show.beatOffsetMs, 40);
    expect(result.show.sections, hasLength(1));
    expect(result.needsAudio, isTrue);
    expect(result.show.audio!.fileName, 'opener.mp3');
  });

  test('the group is rebuilt from the fixtures that exist here', () {
    final result = import(export());
    expect(result.newGroups, hasLength(1));
    expect(result.newGroups.single.name, 'Front');
    expect(result.newGroups.single.fixtureIds, ['f0', 'f1']);
    expect(result.show.groupIds, [result.newGroups.single.id]);
  });

  test('a group that already exists here is reused, by id or by name', () {
    final byId = import(export(), groups: const [group]);
    expect(byId.newGroups, isEmpty);
    expect(byId.show.groupIds, ['g1']);
    const renamedId = FixtureGroup(id: 'other', name: 'front', iconKey: 'all', fixtureIds: ['f2']);
    final byName = import(export(), groups: const [renamedId]);
    expect(byName.show.groupIds, ['other']);
  });

  test('a round trip within the same project adds no banks and keeps the same targets', () {
    final result = import(export(), banks: const [bank], chases: const [chase], groups: const [group], names: {'Opener'});
    expect(result.items, isNull);
    expect(result.show.cues[0].target!.bankId, 'b1');
    expect(result.show.cues[1].target!.chaseId, 'ch1');
    expect(result.show.name, 'Opener (imported)');
    expect(result.show.id, isNot('show1'));
  });

  test('a rig without the grouped fixtures plays on everything, with a warning', () {
    final other = [PatchedFixture(id: 'x', label: 'Wash', profile: par, universeId: 'u9', startChannel: 100)];
    final result = import(export(), fixtures: other);
    expect(result.newGroups, isEmpty);
    expect(result.show.groupIds, isEmpty);
    expect(result.warnings.join('\n'), contains('Group "Front" has no matching fixtures'));
  });

  test('a missing layer sends its cues to Layer 1 and says so', () {
    final result = import(export(), inLayers: const [Layer(id: layer1Id, name: 'Layer 1', priority: 1)]);
    expect(result.show.cues.map((c) => c.layerId), [layer1Id, layer1Id, layer1Id]);
    expect(result.warnings.join('\n'), contains('Layer "Layer 2"'));
  });

  test('names that are taken get a suffix', () {
    expect(import(export(), names: {'Opener'}).show.name, 'Opener (imported)');
    expect(import(export(), names: {'Opener', 'Opener (imported)'}).show.name, 'Opener (imported 2)');
  });

  test('a show with only stop cues and no items imports fine', () {
    const quiet = SongShow(
      id: 'q',
      name: 'Quiet',
      cues: [SongCue(id: 'c', atBeat: 0, layerId: layer1Id, action: SongCueAction.stop)],
    );
    final text = SongShowExport.collect(
      projectName: 'Club',
      show: quiet,
      allBanks: const [],
      allChases: const [],
      allScenes: const [],
      allFixtures: rig(),
      allLayers: layers,
      allGroups: const [],
    ).encode();
    final result = import(text);
    expect(result.items, isNull);
    expect(result.show.cues.single.action, SongCueAction.stop);
  });

  test('other files are refused with a readable message', () {
    expect(() => import('not json'), throwsA(isA<FormatException>()));
    expect(() => import('{"format":"something-else"}'), throwsA(isA<FormatException>()));
    final items = ShowItemsExport.collect(
      projectName: 'p',
      bankIds: const ['b1'],
      allBanks: const [bank],
      allChases: const [],
      allScenes: const [scene],
      allFixtures: rig(),
      allLayers: layers,
    ).encode();
    expect(() => import(items), throwsA(isA<FormatException>()));
  });

  test('a bank/chase export still imports as before and reports where things went', () {
    final items = ShowItemsExport.collect(
      projectName: 'p',
      bankIds: const ['b1'],
      chaseIds: const ['ch1'],
      allBanks: const [bank],
      allChases: const [chase],
      allScenes: const [scene],
      allFixtures: rig(),
      allLayers: layers,
    ).encode();
    var n = 0;
    final result = importShowItems(
      items,
      fixtures: rig(),
      layers: layers,
      bankNames: {},
      chaseNames: {},
      sceneNames: {},
      newId: () => 'i${n++}',
    );
    expect(result.bankIdMap, {'b1': result.banks.single.id});
    expect(result.chaseIdMap, {'ch1': result.chases.single.id});
  });
}

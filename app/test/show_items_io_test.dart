import 'package:dmx_controller/core/storage/show_items_io.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/builtin_fixtures.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/group_position.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:flutter_test/flutter_test.dart';

final _par = builtInFixtureProfiles.firstWhere((p) => p.id == 'builtin-rgb-par');
final _beam = builtInFixtureProfiles.firstWhere((p) => p.id == 'builtin-moving-head-beam');

PatchedFixture _fx(String id, String label, {int start = 0, bool mover = false}) => PatchedFixture(
  id: id,
  label: label,
  profile: mover ? _beam : _par,
  universeId: 'u1',
  startChannel: start,
);

const _layers = [
  Layer(id: layer1Id, name: 'Layer 1', priority: 1),
  Layer(id: 'L2', name: 'Movers', priority: 2),
];

void main() {
  final rig = [_fx('p1', 'PAR L', start: 0), _fx('p2', 'PAR R', start: 4), _fx('m1', 'MH 1', start: 10, mover: true)];
  final scenes = [
    const Scene(id: 'red', name: 'Red', fixtureValues: {'p1': {1: 255}, 'p2': {1: 255}}),
    Scene(
      id: 'sweep',
      name: 'Sweep',
      fixtureValues: const {'m1': {0: 10, 1: 20}},
      fixtureGroups: const [
        ['m1'],
      ],
      groupPositions: const [GroupPosition(manual: {'m1': PanTilt(1, 2)})],
    ),
    const Scene(id: 'unused', name: 'Unused', fixtureValues: {}),
  ];
  const banks = [
    Bank(
      id: 'b1',
      name: 'Verse',
      sceneSlots: ['red', null, 'sweep'],
      ownTiming: true,
      holdMs: 900,
      slotTimings: [SlotTiming(holdMs: 100, fadeMs: 50)],
    ),
    Bank(id: 'b2', name: 'Other', sceneSlots: ['unused']),
  ];
  const chases = [
    Chase(id: 'c1', name: 'Show', steps: [
      ChaseStep(bankId: 'b1'),
      ChaseStep(sceneId: 'red', layerId: 'L2'),
    ]),
  ];

  ShowItemsExport exportOf({List<String> bankIds = const [], List<String> chaseIds = const []}) =>
      ShowItemsExport.collect(
        projectName: 'Club',
        bankIds: bankIds,
        chaseIds: chaseIds,
        allBanks: banks,
        allChases: chases,
        allScenes: scenes,
        allFixtures: rig,
        allLayers: _layers,
      );

  ShowItemsImport importInto(
    String content, {
    List<PatchedFixture>? fixtures,
    List<Layer> layers = _layers,
    Set<String>? bankNames,
  }) {
    var n = 0;
    return importShowItems(
      content,
      fixtures: fixtures ?? rig,
      layers: layers,
      bankNames: bankNames ?? {},
      chaseNames: {},
      sceneNames: {},
      newId: () => 'new${n++}',
    );
  }

  test('a bank exports with exactly the scenes it holds', () {
    final export = exportOf(bankIds: ['b1']);
    expect(export.banks.map((b) => b.id), ['b1']);
    expect(export.scenes.map((s) => s.id), unorderedEquals(['red', 'sweep']));
    expect(export.fixtures.map((f) => f.id), unorderedEquals(['p1', 'p2', 'm1']));
    expect(export.suggestedFileName, 'Verse.dmxitems.json');
  });

  test('a chase brings its banks, their scenes, its own scenes and layers', () {
    final export = exportOf(chaseIds: ['c1']);
    expect(export.chases.single.id, 'c1');
    expect(export.banks.map((b) => b.id), ['b1']);
    expect(export.scenes.map((s) => s.id), unorderedEquals(['red', 'sweep']));
    expect(export.layers.map((l) => l.id), ['L2']);
  });

  test('importing into the same project adds copies wired to each other', () {
    final result = importInto(exportOf(chaseIds: ['c1']).encode());
    expect(result.warnings, isEmpty);
    final red = result.scenes.firstWhere((s) => s.name == 'Red');
    final sweep = result.scenes.firstWhere((s) => s.name == 'Sweep');
    expect(red.id, startsWith('new'));
    expect(red.fixtureValues, {'p1': {1: 255}, 'p2': {1: 255}});
    expect(sweep.groupPositions!.single!.manual, {'m1': const PanTilt(1, 2)});

    final bank = result.banks.single;
    expect(bank.sceneSlots, [red.id, null, sweep.id]);
    expect(bank.ownTiming, isTrue);
    expect(bank.holdMs, 900);
    expect(bank.timingAt(0), const SlotTiming(holdMs: 100, fadeMs: 50));

    final chase = result.chases.single;
    expect(chase.steps[0].bankId, bank.id);
    expect(chase.steps[1].sceneId, red.id);
    expect(chase.steps[1].layerId, 'L2');
    expect(result.summary, 'Imported 1 bank, 1 chase, 2 scenes');
  });

  test('another rig is matched by name, then by address; the rest is reported', () {
    final otherRig = [
      // Same name, different id.
      PatchedFixture(id: 'x1', label: 'par l', profile: _par, universeId: 'u9', startChannel: 40),
      // Different name, same address.
      PatchedFixture(id: 'x2', label: 'Wash', profile: _par, universeId: 'u1', startChannel: 4),
      // The mover isn't here at all.
    ];
    final result = importInto(exportOf(bankIds: ['b1']).encode(), fixtures: otherRig);
    final red = result.scenes.firstWhere((s) => s.name == 'Red');
    expect(red.fixtureValues, {'x1': {1: 255}, 'x2': {1: 255}});
    final sweep = result.scenes.firstWhere((s) => s.name == 'Sweep');
    expect(sweep.fixtureValues, isEmpty);
    expect(sweep.fixtureGroups, isEmpty);
    expect(result.warnings.single, contains('MH 1'));
  });

  test('a fixture with a different channel count is not matched', () {
    final otherRig = [PatchedFixture(id: 'p1', label: 'PAR L', profile: _beam, universeId: 'u1', startChannel: 0)];
    final result = importInto(exportOf(bankIds: ['b1']).encode(), fixtures: otherRig);
    expect(result.scenes.firstWhere((s) => s.name == 'Red').fixtureValues, isEmpty);
  });

  test('a missing layer falls back to Layer 1, and names never clash', () {
    final result = importInto(
      exportOf(chaseIds: ['c1']).encode(),
      layers: const [Layer(id: layer1Id, name: 'Layer 1', priority: 1)],
      bankNames: {'Verse', 'Verse (imported)'},
    );
    expect(result.chases.single.steps[1].layerId, isNull);
    expect(result.warnings.single, contains('Movers'));
    expect(result.banks.single.name, 'Verse (imported 2)');
  });

  test('files that are not an export are refused with a readable message', () {
    expect(() => importInto('not json'), throwsA(isA<FormatException>()));
    expect(() => importInto('{"name": "a project"}'), throwsA(isA<FormatException>()));
    expect(
      () => importInto('{"format": "$showItemsFormat", "formatVersion": 99}'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer version'))),
    );
  });
}

import 'package:dmx_controller/core/storage/project_snapshot.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which bank the Banks screen shows selected used to live only in that
/// screen's own State, so creating a bank (or a Beat Flash preset) selected
/// it for the rest of the session, but saving the project and reopening it
/// — or restarting the app — always landed back on the first bank instead.
/// `selectedBankIdProvider` is now part of the project snapshot, same as
/// the banks themselves.
void main() {
  /// Pumps a bare widget tree just to get a real `WidgetRef` out of it —
  /// `buildProjectSnapshot`/`applyProjectData`/`startProject` all take one,
  /// not a plain `Ref`, so a `ProviderContainer` alone can't call them.
  Future<WidgetRef> pumpRef(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('a saved snapshot carries whichever bank was selected', (tester) async {
    final ref = await pumpRef(tester);
    ref.read(banksProvider.notifier).loadAll(const [
      Bank(id: 'b1', name: 'Bank 1', sceneSlots: [null]),
      Bank(id: 'b2', name: 'Beat Flash', sceneSlots: [null, null], isBeatFlash: true),
    ]);
    ref.read(selectedBankIdProvider.notifier).state = 'b2';

    final snapshot = buildProjectSnapshot(ref);
    expect(snapshot.lastSelectedBankId, 'b2');
  });

  testWidgets('loading a project restores the bank it was last showing', (tester) async {
    final ref = await pumpRef(tester);
    final data = ProjectData(
      name: 'Show',
      settings: const ArtNetSettings(),
      universes: const [],
      customFixtureProfiles: const [],
      patchedFixtures: const [],
      scenes: const [],
      banks: const [
        Bank(id: 'b1', name: 'Bank 1', sceneSlots: [null]),
        Bank(id: 'b2', name: 'Beat Flash', sceneSlots: [null, null], isBeatFlash: true),
      ],
      chases: const [],
      lastSelectedBankId: 'b2',
    );

    applyProjectData(ref, data);
    expect(ref.read(selectedBankIdProvider), 'b2');
  });

  testWidgets('a full-copy new project keeps the selection; a fresh one drops it', (tester) async {
    final ref = await pumpRef(tester);
    final source = ProjectData(
      name: 'Source',
      settings: const ArtNetSettings(),
      universes: const [],
      customFixtureProfiles: const [],
      patchedFixtures: const [],
      scenes: const [],
      banks: const [Bank(id: 'b1', name: 'Beat Flash', sceneSlots: [null], isBeatFlash: true)],
      chases: const [],
      lastSelectedBankId: 'b1',
    );

    startProject(ref, name: 'Copy', carryOver: ProjectCarryOver.everything, source: source);
    expect(ref.read(selectedBankIdProvider), 'b1');

    startProject(ref, name: 'Fresh', carryOver: ProjectCarryOver.empty, source: source);
    expect(ref.read(selectedBankIdProvider), isNull);
  });

  test('ProjectData round-trips lastSelectedBankId through JSON', () {
    final data = ProjectData(
      name: 'Show',
      settings: const ArtNetSettings(),
      universes: const [],
      customFixtureProfiles: const [],
      patchedFixtures: const [],
      scenes: const [],
      banks: const [Bank(id: 'b1', name: 'Bank 1', sceneSlots: [null])],
      chases: const [],
      lastSelectedBankId: 'b1',
    );
    final restored = ProjectData.fromJson(data.toJson(), builtIns: const []);
    expect(restored.lastSelectedBankId, 'b1');
  });

  test('a project saved before this existed loads with no selection', () {
    final restored = ProjectData.fromJson({
      'name': 'Old Show',
      'settings': <String, dynamic>{},
      'universes': [],
      'fixtureProfiles': [],
      'patchedFixtures': [],
      'scenes': [],
      'banks': [],
      'chases': [],
    }, builtIns: const []);
    expect(restored.lastSelectedBankId, isNull);
  });
}

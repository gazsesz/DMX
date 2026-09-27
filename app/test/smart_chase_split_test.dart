import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/core/playback/smart_program_player.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/chases/smart_program_editor_screen.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/chase_providers.dart';
import 'package:dmx_controller/state/smart_program_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentBeats implements BeatSource {
  @override
  Stream<DateTime> get beatEvents => const Stream.empty();
  @override
  bool get isListening => true;
  @override
  String? get lastError => null;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
}

const _l2 = 'layer-2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a chase-lane target survives a save and load, on Layer 1 and the others', () {
    final program = const SmartProgram(id: 'p', name: 'P').withLayerTargets([
      const LayerZoneTargets(layerId: layer1Id, base: ProgramTarget(id: 'c', isBank: false, lane: layer1Id)),
      const LayerZoneTargets(layerId: _l2, faster: ProgramTarget(id: 'c', isBank: false, lane: _l2)),
    ]);
    final restored = SmartProgram.fromJson(program.toJson());
    expect(restored.targetsFor(layer1Id).base, const ProgramTarget(id: 'c', isBank: false, lane: layer1Id));
    expect(restored.targetsFor(_l2).faster, const ProgramTarget(id: 'c', isBank: false, lane: _l2));
    expect(restored.targetsFor(_l2).faster, isNot(const ProgramTarget(id: 'c', isBank: false)));
  });

  test('a lane target plays only that layer\'s steps of the chase', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final players = <String, ChasePlayer>{};
    final smart = SmartProgramPlayer(
      playerFor: (id) => players.putIfAbsent(id, () => _RecordingPlayer()),
      beatService: _SilentBeats(),
    );
    const chase = Chase(id: 'c', name: 'Split', steps: [
      ChaseStep(bankId: 'a'),
      ChaseStep(bankId: 'b', layerId: _l2),
      ChaseStep(bankId: 'c'),
    ]);
    await smart.start(
      program: const SmartProgram(id: 'p', name: 'P').withLayerTargets([
        const LayerZoneTargets(layerId: _l2, base: ProgramTarget(id: 'c', isBank: false, lane: layer1Id)),
      ]),
      chases: const [chase],
      scenes: const [],
      banks: const [],
      patchedFixtures: const [],
      universes: const [],
      service: service,
    );
    expect((players[_l2]! as _RecordingPlayer).played!.steps.map((s) => s.bankId), ['a', 'c']);
    smart.dispose();
    await service.disconnect();
  });

  group('picking a bank-split chase in the editor', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => null,
      );
      SharedPreferences.setMockInitialValues({});
    });

    Future<ProviderContainer> openEditor(WidgetTester tester, Chase chase) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(banksProvider.notifier).loadAll(const [
        Bank(id: 'rgb', name: 'RGB Wave', sceneSlots: [null]),
        Bank(id: 'robot', name: 'Robot Sweep', sceneSlots: [null]),
        Bank(id: 'robot2', name: 'Robot Tilt', sceneSlots: [null]),
      ]);
      container.read(chasesProvider.notifier).loadAll([chase]);
      final program = container.read(smartProgramsProvider.notifier).create('Club');
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: SmartProgramEditorScreen(existing: program)),
      ));
      await tester.pump();
      // Layer 1's Base row: open it and pick the chase.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chase · ${chase.name}').last);
      await tester.pumpAndSettle();
      return container;
    }

    Future<SmartProgram> save(WidgetTester tester, ProviderContainer container) async {
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      return container.read(smartProgramsProvider).single;
    }

    const split = Chase(id: 'show', name: 'Show', steps: [
      ChaseStep(bankId: 'rgb'),
      ChaseStep(bankId: 'robot', layerId: _l2),
      ChaseStep(bankId: 'robot2', layerId: _l2),
    ]);

    testWidgets('Szétosztás puts each layer\'s banks on that layer', (tester) async {
      final container = await openEditor(tester, split);
      expect(find.textContaining('több rétegen fut'), findsOneWidget);
      await tester.tap(find.text('Szétosztás'));
      await tester.pumpAndSettle();
      final program = await save(tester, container);
      expect(program.targetsFor(layer1Id).base, const ProgramTarget(id: 'rgb', isBank: true),
          reason: 'a single bank on the layer becomes that bank');
      expect(program.targetsFor(_l2).base, const ProgramTarget(id: 'show', isBank: false, lane: _l2),
          reason: 'two banks on the layer become its share of the chase');
    });

    testWidgets('Mind ezen a rétegen keeps the whole chase on the row it was picked on', (tester) async {
      final container = await openEditor(tester, split);
      await tester.tap(find.text('Mind ezen a rétegen'));
      await tester.pumpAndSettle();
      final program = await save(tester, container);
      expect(program.targetsFor(layer1Id).base, const ProgramTarget(id: 'show', isBank: false));
      expect(program.targetsFor(_l2).base, isNull);
    });

    testWidgets('a chase with scene steps is not offered for splitting', (tester) async {
      await openEditor(tester, const Chase(id: 'mix', name: 'Mixed', steps: [
        ChaseStep(sceneId: 's1'),
        ChaseStep(bankId: 'robot', layerId: _l2),
      ]));
      expect(find.textContaining('több rétegen fut'), findsNothing);
    });
  });
}

/// Records what it was asked to play instead of running it.
class _RecordingPlayer extends ChasePlayer {
  Chase? played;

  @override
  Future<void> play({
    required Chase chase,
    required List<Scene> scenes,
    required List<Bank> banks,
    required patchedFixtures,
    required universes,
    required ArtNetService service,
    Stream<DateTime>? beatStream,
    BeatRate beatRate = BeatRate.normal,
    void Function(int instantIndex)? onStep,
    Duration? Function()? fadeOverride,
    Duration flashLength = const Duration(milliseconds: 80),
    BeatRate Function()? liveBeatRate,
    Duration Function()? liveFlashLength,
    bool Function()? liveBeatSync,
    bool Function()? liveBeatAvailable,
    Duration Function()? liveFlashGap,
    List<Bank> Function()? liveBanks,
    List<Scene> Function()? liveScenes,
    bool claim = true,
  }) async {
    played = chase;
  }
}

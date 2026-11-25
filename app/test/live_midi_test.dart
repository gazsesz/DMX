import 'package:dmx_controller/features/live/live_screen.dart';
import 'package:dmx_controller/core/midi/midi_control_service.dart';
import 'package:dmx_controller/core/midi/midi_input_message.dart';
import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/models/midi_mapping.dart';
import 'package:dmx_controller/state/live_midi_providers.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/midi_control_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MidiTrigger _n(int number, {int ch = 9}) => MidiTrigger(kind: MidiTriggerKind.note, channel: ch, number: number);

MidiInputMessage _press(int number, {int ch = 9}) =>
    MidiInputMessage(kind: MidiTriggerKind.note, channel: ch, number: number, value: 100);

void main() {
  group('4×4 pad block', () {
    final grid = LiveGrid.starter();

    test('skips lanes with no clips up top, and follows the controller\'s numbering', () {
      final lanes = padLanes(grid);
      expect(lanes.first.id, isNot('show'), reason: 'the empty Show lane gets no pads');

      // Pads numbered bottom-up (top-left 48, the one under it 44).
      final block = padBlock(grid, topLeft: _n(48), below: _n(44));
      final byPad = {for (final (target, trigger) in block) trigger.number: target};
      expect(byPad[48], LiveMidiTarget.clip(lanes[0].id, grid.rowIds[0]));
      expect(byPad[49], LiveMidiTarget.clip(lanes[1].id, grid.rowIds[0]));
      expect(byPad[44], LiveMidiTarget.clip(lanes[0].id, grid.rowIds[1]));
      expect(block.every((b) => b.$2.channel == 9), isTrue);
      expect(block.length, lessThanOrEqualTo(16));

      // Top-down numbering works the same way.
      final down = padBlock(grid, topLeft: _n(36), below: _n(40));
      expect({for (final (t, trig) in down) trig.number: t}[40], LiveMidiTarget.clip(lanes[0].id, grid.rowIds[1]));
    });
  });

  group('pads on the Grid', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late ProviderContainer container;
    late MidiControlController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => null,
      );
      container = ProviderContainer();
      controller = MidiControlController(container.read, MidiControlService());
    });

    tearDown(() {
      container.read(liveEngineProvider).stopAll();
      container.dispose();
    });

    Future<void> press(int number) async {
      controller.service.handleMessage(_press(number));
      await Future<void>.delayed(Duration.zero);
    }

    test('a pad marks its clip NEXT, GO switches it, Stop all ends it', () async {
      final grid = container.read(liveGridProvider);
      assignLiveMidi(container.read, LiveMidiTarget.clip('moves', grid.rowIds[1]), _n(36));
      assignLiveMidi(container.read, const LiveMidiTarget.go(), _n(37));
      assignLiveMidi(container.read, const LiveMidiTarget.stopAll(), _n(38));
      container.read(livePrefsProvider.notifier).setQuantize(LiveQuantize.now);
      final engine = container.read(liveEngineProvider);

      await press(36);
      expect(engine.status.queued['moves'], 1);
      await press(37);
      engine.tick(0);
      expect(engine.status.running['moves'], 1);
      await press(38);
      expect(engine.status.anyRunning, isFalse);
    });

    test('the pad follows its row when rows move, and a row pad launches the row', () async {
      final notifier = container.read(liveGridProvider.notifier);
      final rowId = container.read(liveGridProvider).rowIds[2];
      assignLiveMidi(container.read, LiveMidiTarget.row(rowId), _n(40));
      notifier.removeRow(0);
      container.read(livePrefsProvider.notifier).setPadMode(LivePadMode.launchDirectly);
      container.read(livePrefsProvider.notifier).setQuantize(LiveQuantize.now);
      final engine = container.read(liveEngineProvider);
      await press(40);
      engine.tick(0);
      expect(engine.status.running.values.toSet(), {1}, reason: 'row 2 is row 1 now');
    });

    test('one pad per target, one target per pad', () {
      final grid = container.read(liveGridProvider);
      final a = LiveMidiTarget.clip('moves', grid.rowIds[0]);
      final b = LiveMidiTarget.clip('level', grid.rowIds[0]);
      assignLiveMidi(container.read, a, _n(36));
      assignLiveMidi(container.read, a, _n(37));
      var all = container.read(midiMappingsProvider);
      expect(all.length, 1);
      expect(liveMidiMappingFor(all, a)!.trigger.number, 37);

      assignLiveMidi(container.read, b, _n(37));
      all = container.read(midiMappingsProvider);
      expect(liveMidiMappingFor(all, a), isNull, reason: 'the pad moved to the other clip');
      expect(liveMidiMappingFor(all, b)!.trigger.number, 37);

      expect(clearLiveMidi(container.read, b), isTrue);
      expect(container.read(midiMappingsProvider), isEmpty);
    });

    test('Grid mappings survive the project file', () {
      final m = LiveMidiTarget.clip('moves', 'r1').mappingFor(_n(36), id: 'x');
      final back = MidiMapping.fromJson(m.toJson())!;
      expect(back.action, MidiActionKind.liveClip);
      expect(back.param, 'moves');
      expect(back.targetId, 'r1');
    });
  });

  testWidgets('MIDI button: learn mode taps don\'t play, badges show bound pads', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final grid = container.read(liveGridProvider);
    assignLiveMidi(container.read, LiveMidiTarget.clip('colors-pars', grid.rowIds[0]), _n(36));
    await tester.pump();
    expect(find.text('C1'), findsOneWidget, reason: 'the bound pad shows on the clip');

    await tester.tap(find.byKey(const ValueKey('live-midi-learn')));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-midi-banner')), findsOneWidget);

    // No controller connected: says so, and the tap does not queue the clip.
    await tester.tap(find.text('Warm wash'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(liveStatusProvider).queued, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);

    // Long press while learning removes the pad.
    await tester.longPress(find.text('Warm wash'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(midiMappingsProvider), isEmpty);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

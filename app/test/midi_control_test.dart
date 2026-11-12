import 'package:dmx_controller/core/midi/midi_control_service.dart';
import 'package:dmx_controller/core/midi/midi_input_message.dart';
import 'package:dmx_controller/core/midi/midi_mapping_engine.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/midi_mapping.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/color_override_providers.dart';
import 'package:dmx_controller/state/dimmer_dropout_providers.dart';
import 'package:dmx_controller/state/midi_control_providers.dart';
import 'package:dmx_controller/state/movement_live_providers.dart';
import 'package:dmx_controller/state/tempo_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MidiInputMessage _note(int n, {int ch = 0, int vel = 100}) =>
    MidiInputMessage(kind: MidiTriggerKind.note, channel: ch, number: n, value: vel, noteOff: vel == 0);

MidiInputMessage _cc(int n, int value, {int ch = 0}) =>
    MidiInputMessage(kind: MidiTriggerKind.cc, channel: ch, number: n, value: value);

MidiMapping _map(String id, MidiTriggerKind kind, int number, MidiActionKind action, {String? param}) =>
    MidiMapping(
      id: id,
      trigger: MidiTrigger(kind: kind, channel: 0, number: number),
      action: action,
      param: param,
    );

void main() {
  group('parseMidiPacket', () {
    test('decodes note on/off, CC and program change', () {
      final messages = parseMidiPacket([0x90, 60, 100, 0x80, 60, 0, 0xB1, 7, 64, 0xC2, 5]);
      expect(messages.map((m) => m.toString()), [
        'Note C3 · ch 1 = 100',
        'Note C3 · ch 1 = 0 (off)',
        'CC 7 · ch 2 = 64',
        'PC 6 · ch 3 = 0',
      ]);
    });

    test('note on with velocity 0 counts as a release', () {
      final m = parseMidiPacket([0x90, 36, 0]).single;
      expect(m.noteOff, isTrue);
    });

    test('running status, across packets too', () {
      final running = MidiRunningStatus();
      final first = parseMidiPacket([0xB0, 1, 10, 1, 20], running);
      final second = parseMidiPacket([1, 30], running);
      expect([...first, ...second].map((m) => m.value), [10, 20, 30]);
    });

    test('clock bytes in the middle of a message are skipped, sysex is skipped whole', () {
      final messages = parseMidiPacket([0xF8, 0x90, 0xF8, 40, 0xFA, 99, 0xF0, 1, 2, 3, 0xF7, 0xB0, 2, 3]);
      expect(messages.length, 2);
      expect(messages[0].number, 40);
      expect(messages[0].value, 99);
      expect(messages[1].kind, MidiTriggerKind.cc);
    });

    test('data without a status byte is ignored', () {
      expect(parseMidiPacket([10, 20, 30]), isEmpty);
    });
  });

  group('MidiMappingEngine', () {
    final pad = _map('pad', MidiTriggerKind.note, 36, MidiActionKind.blackout);
    final ccButton = _map('ccb', MidiTriggerKind.cc, 20, MidiActionKind.stop);
    final fader = _map('fader', MidiTriggerKind.cc, 7, MidiActionKind.grandMaster);

    test('a pad fires on press, not on release, and only its own note', () {
      final engine = MidiMappingEngine();
      expect(engine.handle(_note(36), [pad]).single.mapping.id, 'pad');
      expect(engine.handle(_note(36, vel: 0), [pad]), isEmpty);
      expect(engine.handle(_note(37), [pad]), isEmpty);
      expect(engine.handle(_note(36, ch: 1), [pad]), isEmpty);
    });

    test('a CC button fires once per press (crossing 64 upwards)', () {
      final engine = MidiMappingEngine();
      expect(engine.handle(_cc(20, 127), [ccButton]), hasLength(1));
      expect(engine.handle(_cc(20, 127), [ccButton]), isEmpty);
      expect(engine.handle(_cc(20, 0), [ccButton]), isEmpty);
      expect(engine.handle(_cc(20, 127), [ccButton]), hasLength(1));
    });

    test('a fader follows its value', () {
      final engine = MidiMappingEngine();
      expect(engine.handle(_cc(7, 0), [fader]).single.value, 0);
      expect(engine.handle(_cc(7, 127), [fader]).single.value, 1);
      expect(engine.handle(_cc(7, 64), [fader]).single.value, closeTo(0.504, 0.001));
    });
  });

  test('tap tempo averages the taps and restarts after a long gap', () {
    final tap = TapTempo();
    final t0 = DateTime(2026);
    expect(tap.tap(t0), isNull);
    expect(tap.tap(t0.add(const Duration(milliseconds: 500))), closeTo(120, 0.01));
    expect(tap.tap(t0.add(const Duration(milliseconds: 1000))), closeTo(120, 0.01));
    // Long pause: a fresh sequence.
    expect(tap.tap(t0.add(const Duration(seconds: 10))), isNull);
  });

  group('MidiMapping persistence', () {
    test('round-trips through JSON, drops unknown actions', () {
      final mapping = MidiMapping(
        id: 'm1',
        trigger: const MidiTrigger(kind: MidiTriggerKind.cc, channel: 3, number: 21),
        action: MidiActionKind.playTarget,
        targetKind: MidiTargetKind.smart,
        targetId: 's1',
      );
      final back = MidiMapping.fromJson(mapping.toJson())!;
      expect(back.trigger, mapping.trigger);
      expect(back.action, MidiActionKind.playTarget);
      expect(back.targetKind, MidiTargetKind.smart);
      expect(back.targetId, 's1');
      expect(MidiMapping.fromJson({'action': 'teleport', 'trigger': mapping.trigger.toJson()}), isNull);
    });

    test('travels with the project file; old files load with none', () {
      final data = ProjectData(
        name: 'Show',
        settings: const ArtNetSettings(),
        universes: const [],
        customFixtureProfiles: const [],
        patchedFixtures: const [],
        scenes: const [],
        banks: const [],
        chases: const [],
        midiMappings: [_map('m1', MidiTriggerKind.note, 36, MidiActionKind.blackout)],
      );
      final json = data.toJson();
      final back = ProjectData.fromJson(json, builtIns: const []);
      expect(back.midiMappings.single.action, MidiActionKind.blackout);
      json.remove('midiMappings');
      expect(ProjectData.fromJson(json, builtIns: const []).midiMappings, isEmpty);
    });

    test('remembered devices survive encode/decode', () {
      const d = RememberedMidiDevice(id: 'usb-1', name: 'APC mini mk2', bluetooth: true);
      final back = RememberedMidiDevice.decode(d.encode())!;
      expect(back.id, 'usb-1');
      expect(back.name, 'APC mini mk2');
      expect(back.bluetooth, isTrue);
      expect(RememberedMidiDevice.decode('junk'), isNull);
    });
  });

  group('MidiMappingsNotifier', () {
    test('saving a mapping on a control that is already bound replaces the old one', () {
      final notifier = MidiMappingsNotifier();
      final first = notifier.save(_map('', MidiTriggerKind.note, 36, MidiActionKind.blackout));
      expect(first.id, isNotEmpty);
      notifier.save(_map('', MidiTriggerKind.note, 37, MidiActionKind.stop));
      notifier.save(_map('', MidiTriggerKind.note, 36, MidiActionKind.dropout));
      expect(notifier.state.map((m) => m.action), [MidiActionKind.stop, MidiActionKind.dropout]);
    });

    test('editing keeps the mapping in its place', () {
      final notifier = MidiMappingsNotifier();
      final a = notifier.save(_map('', MidiTriggerKind.note, 1, MidiActionKind.stop));
      notifier.save(_map('', MidiTriggerKind.note, 2, MidiActionKind.blackout));
      notifier.save(a.copyWith(action: MidiActionKind.resume));
      expect(notifier.state.first.action, MidiActionKind.resume);
    });
  });

  group('controller → app', () {
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

    tearDown(() => container.dispose());

    Future<void> send(MidiInputMessage m) async {
      controller.service.handleMessage(m);
      await Future<void>.delayed(Duration.zero);
    }

    test('a fader drives the grand master and the movement knobs', () async {
      container.read(midiMappingsProvider.notifier).loadAll([
        _map('gm', MidiTriggerKind.cc, 7, MidiActionKind.grandMaster),
        _map('sz', MidiTriggerKind.cc, 8, MidiActionKind.movementSize),
      ]);
      await send(_cc(7, 0));
      expect(container.read(grandMasterProvider), 0);
      await send(_cc(7, 127));
      expect(container.read(grandMasterProvider), 1);
      await send(_cc(8, 127));
      expect(container.read(movementLiveProvider).size, closeTo(2, 0.001));
      expect(controller.lastFiredId.value, 'sz');
    });

    test('pads toggle the dropout and set a colour', () async {
      container.read(midiMappingsProvider.notifier).loadAll([
        _map('dr', MidiTriggerKind.note, 36, MidiActionKind.dropout),
        _map('blue', MidiTriggerKind.note, 37, MidiActionKind.color, param: 'blue'),
        _map('scene', MidiTriggerKind.note, 38, MidiActionKind.color, param: 'off'),
      ]);
      final before = container.read(dimmerDropoutProvider).enabled;
      await send(_note(36));
      expect(container.read(dimmerDropoutProvider).enabled, !before);
      await send(_note(36, vel: 0));
      expect(container.read(dimmerDropoutProvider).enabled, !before);
      await send(_note(37));
      expect(container.read(liveColorProvider).color?.id, 'blue');
      await send(_note(38));
      expect(container.read(liveColorProvider).color, isNull);
    });

    test('tap tempo sets the step speed', () async {
      container.read(midiMappingsProvider.notifier).loadAll([
        _map('tap', MidiTriggerKind.note, 40, MidiActionKind.tapTempo),
      ]);
      await send(_note(40));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await send(_note(40));
      final bpm = container.read(tempoProvider).bpm;
      expect(bpm, greaterThan(120));
      expect(bpm, lessThan(240));
    });

    test('a pad bound to a bank reports why it could not start', () async {
      container.read(banksProvider.notifier).loadAll([
        Bank(id: 'b1', name: 'Front Wash', sceneSlots: List.filled(4, null)),
      ]);
      container.read(midiMappingsProvider.notifier).loadAll([
        const MidiMapping(
          id: 'p',
          trigger: MidiTrigger(kind: MidiTriggerKind.note, channel: 0, number: 50),
          action: MidiActionKind.playTarget,
          targetKind: MidiTargetKind.bank,
          targetId: 'b1',
        ),
      ]);
      await send(_note(50));
      // No Art-Net node in a test — the same answer a Dashboard tile gives.
      expect(controller.lastResult.value, 'Not connected — check Settings');
      expect(midiTargetName(container.read, container.read(midiMappingsProvider).single), 'Front Wash');
    });

    test('while learning, the next press is captured and nothing fires', () async {
      container.read(midiMappingsProvider.notifier).loadAll([
        _map('dr', MidiTriggerKind.note, 36, MidiActionKind.dropout),
      ]);
      final before = container.read(dimmerDropoutProvider).enabled;
      final learned = controller.service.learn();
      controller.service.handleMessage(_note(36, vel: 0)); // a release is not learned
      controller.service.handleMessage(_note(36));
      final message = await learned;
      expect(message!.trigger, const MidiTrigger(kind: MidiTriggerKind.note, channel: 0, number: 36));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(dimmerDropoutProvider).enabled, before);
      expect(controller.service.isLearning, isFalse);
    });

    test('cancelling learn completes with null', () async {
      final learned = controller.service.learn();
      controller.service.cancelLearn();
      expect(await learned, isNull);
    });
  });
}

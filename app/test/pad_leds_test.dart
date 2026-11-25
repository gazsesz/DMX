import 'package:dmx_controller/core/live/live_engine.dart';
import 'package:dmx_controller/core/midi/pad_leds.dart';
import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/models/midi_mapping.dart';
import 'package:dmx_controller/state/live_midi_providers.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/midi_control_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MidiTrigger _n(int number, {int ch = 9}) => MidiTrigger(kind: MidiTriggerKind.note, channel: ch, number: number);

void main() {
  final grid = LiveGrid.starter();
  final mappings = [
    LiveMidiTarget.clip('moves', grid.rowIds[0]).mappingFor(_n(36), id: 'a'),
    LiveMidiTarget.clip('moves', grid.rowIds[1]).mappingFor(_n(37), id: 'b'),
    LiveMidiTarget.clip('show', grid.rowIds[0]).mappingFor(_n(38), id: 'c'),
    const LiveMidiTarget.go().mappingFor(_n(39), id: 'd'),
    const LiveMidiTarget.stopAll().mappingFor(_n(40), id: 'e'),
    // A CC button can't be lit by a Note On.
    const LiveMidiTarget.go().mappingFor(const MidiTrigger(kind: MidiTriggerKind.cc, channel: 0, number: 20), id: 'f'),
  ];

  test('pads show running, NEXT, ready and empty', () {
    final idle = liveLedState(grid: grid, status: const LiveStatus(), mappings: mappings);
    expect(idle[_n(36)], PadLed.ready);
    expect(idle[_n(38)], PadLed.off, reason: 'the Show lane has no clip there');
    expect(idle[_n(39)], PadLed.off, reason: 'nothing waits for GO');
    expect(idle[_n(40)], PadLed.off);
    expect(idle.length, 5, reason: 'the CC button is left alone');

    final live = liveLedState(
      grid: grid,
      status: const LiveStatus(running: {'moves': 0}, queued: {'moves': 1}),
      mappings: mappings,
    );
    expect(live[_n(36)], PadLed.green);
    expect(live[_n(37)], PadLed.orange);
    expect(live[_n(39)], PadLed.orange);
    expect(live[_n(40)], PadLed.redPink);
  });

  test('colours go out paced, only when they change, and dark when a pad is dropped', () async {
    final sent = <List<int>>[];
    final sender = PadLedSender(sent.add, pace: const Duration(milliseconds: 1));
    addTearDown(sender.dispose);
    sender.update({_n(36): PadLed.green, _n(37): PadLed.ready});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, [
      [0x99, 36, PadLed.green],
      [0x99, 37, PadLed.ready],
    ]);

    sent.clear();
    sender.update({_n(36): PadLed.green});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, [
      [0x99, 37, PadLed.off],
    ]);

    sent.clear();
    sender.forget();
    sender.update({_n(36): PadLed.green});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, [
      [0x99, 36, PadLed.green],
    ], reason: 'a reconnected pad gets everything again');
  });

  test('the LED test uses the mapped pads and the SMC-PAD\'s usual notes', () {
    expect(ledTestPads(mappings).toSet().containsAll({_n(36), _n(37), _n(38), _n(39), _n(40)}), isTrue);
    expect(ledTestPads(mappings).length, 32);
    expect(ledTestPads(const []).length, 32);
  });

  group('export / import', () {
    test('a mapping file round-trips, and a project file\'s mappings are read too', () {
      final file = midiMappingsToFile(mappings);
      expect(midiMappingsFromFile(file)!.length, mappings.length);
      expect(midiMappingsFromFile({'name': 'Show', 'midiMappings': file['mappings']})!.length, mappings.length);
      expect(midiMappingsFromFile({'something': 'else'}), isNull);
    });

    test('replace or add; missing targets are spotted', () {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final rowId = c.read(liveGridProvider).rowIds[0];
      c.read(midiMappingsProvider.notifier).loadAll([
        MidiMapping(id: 'old', trigger: _n(50), action: MidiActionKind.stop),
      ]);
      final imported = [
        LiveMidiTarget.clip('moves', rowId).mappingFor(_n(36), id: 'x'),
        LiveMidiTarget.clip('nope', rowId).mappingFor(_n(37), id: 'y'),
      ];
      applyImportedMappings(c.read, imported, replace: false);
      expect(c.read(midiMappingsProvider).length, 3);
      applyImportedMappings(c.read, imported, replace: true);
      expect(c.read(midiMappingsProvider).map((m) => m.id), ['x', 'y']);
      expect(midiMappingTargetExists(c.read, imported[0]), isTrue);
      expect(midiMappingTargetExists(c.read, imported[1]), isFalse);
    });
  });
}

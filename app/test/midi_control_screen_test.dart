import 'package:dmx_controller/core/midi/midi_input_message.dart';
import 'package:dmx_controller/features/settings/midi_control_screen.dart';
import 'package:dmx_controller/models/midi_mapping.dart';
import 'package:dmx_controller/state/midi_control_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add a mapping with MIDI learn, then it shows in the list', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MidiControlScreen()),
      ),
    );
    // The device list gives up on a platform with no MIDI service.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Nothing mapped yet. Tap Add mapping.'), findsOneWidget);

    await tester.tap(find.text('Add mapping'));
    await tester.pumpAndSettle();
    // A new mapping listens straight away.
    expect(find.text('Press the pad or button on the controller…'), findsOneWidget);

    container.read(midiControlProvider).service.handleMessage(
      const MidiInputMessage(kind: MidiTriggerKind.note, channel: 0, number: 36, value: 127),
    );
    await tester.pumpAndSettle();
    expect(find.text('Note C1 · ch 1'), findsWidgets);

    // Pick "Blackout" instead of the default Play / stop.
    await tester.tap(find.byType(DropdownButtonFormField<MidiActionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blackout').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final mappings = container.read(midiMappingsProvider);
    expect(mappings.single.action, MidiActionKind.blackout);
    expect(mappings.single.trigger.number, 36);
    expect(find.text('Blackout'), findsOneWidget);
    expect(find.text('Note C1 · ch 1'), findsOneWidget);

    // The monitor shows what came in.
    expect(find.textContaining('Last: Note C1'), findsOneWidget);
  });
}

import 'package:dmx_controller/core/widgets/control_dock.dart';
import 'package:dmx_controller/models/control_dock_prefs.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ControlDockPosition position, {List<Override> overrides = const []}) {
  // Mirrors how AppShell docks it: bottom takes the full width under the
  // content, right takes the full height beside it.
  final dock = ControlDock(position: position);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: position == ControlDockPosition.bottom
            ? Column(children: [const Expanded(child: SizedBox.expand()), dock])
            : Row(children: [const Expanded(child: SizedBox.expand()), dock]),
      ),
    ),
  );
}

void main() {
  testWidgets('renders docked at the bottom with nothing playing', (tester) async {
    await tester.pumpWidget(_host(ControlDockPosition.bottom));
    expect(tester.takeException(), isNull);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Blackout'), findsOneWidget);
    expect(find.text('Beat'), findsOneWidget);
  });

  testWidgets('renders docked on the right', (tester) async {
    await tester.pumpWidget(_host(ControlDockPosition.right));
    expect(tester.takeException(), isNull);
    expect(find.text('Blackout'), findsOneWidget);
  });

  testWidgets('live stage strip renders along the bottom', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [Expanded(child: SizedBox.expand()), LiveStageDock()]),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveStageDock), findsOneWidget);
  });

  testWidgets('shows what is playing instead of Idle', (tester) async {
    await tester.pumpWidget(
      _host(
        ControlDockPosition.bottom,
        overrides: [
          nowPlayingProvider.overrideWith(
            (ref) => const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash'),
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Front Wash'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });
}

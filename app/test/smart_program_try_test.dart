import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/chases/smart_program_editor_screen.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Smart Program editor's per-zone "Try": plays the zone's layers and
/// Grid row right away, and stops when tried again or when the editor goes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Try plays a zone and stops on a second tap and on leaving', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true)));
    container.read(scenesProvider.notifier).upsert(const Scene(id: 's1', name: 'One', fixtureValues: {}));
    final bankId = container.read(banksProvider).first.id;
    container.read(banksProvider.notifier).setSlot(bankId, 0, 's1');
    final rowId = container.read(liveGridProvider).rowIds[1];
    final program = const SmartProgram(id: 'p', name: 'Club')
        .withLayerTargets([LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: bankId))])
        .copyWith(gridRows: {SmartProgramZone.base: rowId});

    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: SmartProgramEditorScreen(existing: program)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('smart-try-base')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);
    expect(container.read(liveEngineProvider).isRowRunning(1), isTrue);

    await tester.tap(find.byKey(const ValueKey('smart-try-base')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isFalse);
    expect(container.read(liveStatusProvider).anyRunning, isFalse);

    // Started again, then the editor is left: it stops.
    await tester.tap(find.byKey(const ValueKey('smart-try-base')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isFalse);
    expect(container.read(liveStatusProvider).anyRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
  });
}

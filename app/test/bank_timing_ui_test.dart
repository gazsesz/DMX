import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/banks/banks_screen.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Changing a running bank's timing from its sheet restarts the bank from
/// inside that sheet. The restarted player used to read the beat rate and
/// fade through the sheet's own `ref` on every step — which throws once the
/// sheet is closed, so the bank stopped stepping the moment you closed it
/// while still showing as running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a bank switched to its own timing keeps stepping after the sheet closes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true)));
    container.read(scenesProvider.notifier)
      ..upsert(const Scene(id: 's1', name: 'One', fixtureValues: {}))
      ..upsert(const Scene(id: 's2', name: 'Two', fixtureValues: {}));
    final bankId = container.read(banksProvider).first.id;
    container.read(banksProvider.notifier)
      ..setSlot(bankId, 0, 's1')
      ..setSlot(bankId, 1, 's2')
      ..setTiming(bankId, holdMs: 60, fadeMs: 0);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BanksScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Run Bank'));
    await tester.pump(const Duration(milliseconds: 50));
    final player = container.read(chasePlayerProvider(layer1Id));
    expect(player.isPlaying, isTrue);

    await tester.tap(find.byIcon(Icons.tune).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Own timing for this bank'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(banksProvider).first.ownTiming, isTrue);

    // Close the sheet, then give the bank time for a handful of 60 ms steps.
    Navigator.of(tester.element(find.text('Own timing for this bank'))).pop();
    final seen = <int?>{};
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(container.read(layerStepProvider(layer1Id)));
    }
    expect(player.isPlaying, isTrue);
    expect(seen, containsAll([0, 1]), reason: 'the bank stopped stepping once the sheet closed');
    expect(tester.takeException(), isNull);

    player.stop();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

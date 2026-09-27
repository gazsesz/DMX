import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  test('changing a running bank\'s own timing keeps it running', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true));
    container.read(scenesProvider.notifier).upsert(const Scene(id: 's1', name: 'Look', fixtureValues: {}));
    final bank = container.read(banksProvider).first;
    container.read(banksProvider.notifier).setSlot(bank.id, 0, 's1');

    expect(runBankOnLayer(container.read, bank: container.read(banksProvider).first, layerId: layer1Id), isNull);
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);

    container.read(banksProvider.notifier).setTiming(bank.id, ownTiming: true);
    restartBankEverywhere(container.read, bank.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);
    expect(container.read(nowPlayingProvider)?.id, bank.id);

    container.read(banksProvider.notifier).setTiming(bank.id, holdMs: 400);
    restartBankEverywhere(container.read, bank.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);
  });
}

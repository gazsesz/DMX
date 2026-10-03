import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/state/layer_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stopLayersExcept clears every layer but the ones kept', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final layers = container.read(layersProvider);
    final other = layers.firstWhere((l) => l.id != layer1Id, orElse: () => layers.first).id;
    const playing = NowPlaying(id: 'c', kind: PlaybackKind.chase, name: 'Old');
    for (final l in layers) {
      container.read(nowPlayingForLayerProvider(l.id).notifier).state = playing;
    }

    stopLayersExcept(container.read, [layer1Id]);

    expect(container.read(nowPlayingForLayerProvider(layer1Id)), isNotNull);
    if (other != layer1Id) {
      expect(container.read(nowPlayingForLayerProvider(other)), isNull);
      expect(container.read(lastPlayedForLayerProvider(other))?.id, 'c', reason: 'remembered for Resume');
    }
  });
}

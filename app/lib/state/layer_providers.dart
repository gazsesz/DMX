import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/layer.dart';

const _uuid = Uuid();

final layersProvider = StateNotifierProvider<LayersNotifier, List<Layer>>((ref) {
  return LayersNotifier();
});

class LayersNotifier extends StateNotifier<List<Layer>> {
  LayersNotifier() : super(_defaultSeed());

  static List<Layer> _defaultSeed() => const [
    Layer(id: layer1Id, name: 'Layer 1', priority: 1, mergeHint: 'HTP dimmer'),
    Layer(id: layer2Id, name: 'Layer 2', priority: 2, mergeHint: 'LTP pan/tilt'),
  ];

  Layer addLayer() {
    final layer = Layer(id: _uuid.v4(), name: 'Layer ${state.length + 1}', priority: state.length + 1);
    state = [...state, layer];
    return layer;
  }

  void rename(String id, String name) {
    state = [
      for (final l in state)
        if (l.id == id) l.copyWith(name: name) else l,
    ];
  }

  void setMergeHint(String id, String hint) {
    state = [
      for (final l in state)
        if (l.id == id) l.copyWith(mergeHint: hint) else l,
    ];
  }

  /// No-op for [layer1Id] — every screen that predates multi-layer support
  /// assumes it always exists, so this is the one invariant the notifier
  /// enforces itself rather than trusting every call site to check first.
  void remove(String id) {
    if (id == layer1Id) return;
    state = state.where((l) => l.id != id).toList();
  }

  /// Guards the same invariant on load: an old project file saved before
  /// this feature existed has no "layers" key at all (empty list here), and
  /// a hand-edited one could omit [layer1Id] outright.
  void loadAll(List<Layer> layers) {
    if (layers.any((l) => l.id == layer1Id)) {
      state = layers;
    } else {
      state = [const Layer(id: layer1Id, name: 'Layer 1', priority: 1, mergeHint: 'HTP dimmer'), ...layers];
    }
  }

  void reset() {
    state = _defaultSeed();
  }
}

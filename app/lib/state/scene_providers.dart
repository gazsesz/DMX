import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/scene.dart';

const _uuid = Uuid();

final scenesProvider = StateNotifierProvider<ScenesNotifier, List<Scene>>((ref) {
  return ScenesNotifier();
});

class ScenesNotifier extends StateNotifier<List<Scene>> {
  ScenesNotifier() : super(const []);

  Scene create(String name, Map<String, List<int>> fixtureValues) {
    final scene = Scene(id: _uuid.v4(), name: name, fixtureValues: fixtureValues);
    state = [...state, scene];
    return scene;
  }

  void upsert(Scene scene) {
    final exists = state.any((s) => s.id == scene.id);
    state = exists
        ? [for (final s in state) if (s.id == scene.id) scene else s]
        : [...state, scene];
  }

  /// Returns the new copy, so callers can immediately do something with it
  /// (e.g. file it into the same bank the original was duplicated from).
  Scene? duplicate(String id) {
    final source = state.where((s) => s.id == id);
    if (source.isEmpty) return null;
    final copy = source.first;
    final duplicated = Scene(id: _uuid.v4(), name: '${copy.name} Copy', fixtureValues: copy.fixtureValues);
    state = [...state, duplicated];
    return duplicated;
  }

  void rename(String id, String name) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(name: name) else s,
    ];
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  void loadAll(List<Scene> scenes) {
    state = scenes;
  }
}

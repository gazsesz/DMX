import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/fixture_group.dart';

const _uuid = Uuid();

/// Saved fixture groups for the current rig — project-scoped, since a
/// group's fixture ids only mean anything within the project that patched
/// them (see [FixtureGroup]).
final fixtureGroupsProvider = StateNotifierProvider<FixtureGroupsNotifier, List<FixtureGroup>>(
  (ref) => FixtureGroupsNotifier(),
);

class FixtureGroupsNotifier extends StateNotifier<List<FixtureGroup>> {
  FixtureGroupsNotifier() : super(const []);

  FixtureGroup create({required String name, required String iconKey, required List<String> fixtureIds}) {
    final group = FixtureGroup(id: _uuid.v4(), name: name, iconKey: iconKey, fixtureIds: fixtureIds);
    state = [...state, group];
    return group;
  }

  void update(String id, FixtureGroup Function(FixtureGroup current) updater) {
    state = [for (final g in state) if (g.id == id) updater(g) else g];
  }

  /// Riverpod's [ReorderableListView] convention: [newIndex] is the index in
  /// the list *before* the dragged item is removed.
  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    state = list;
  }

  void remove(String id) {
    state = state.where((g) => g.id != id).toList();
  }

  void loadAll(List<FixtureGroup> groups) {
    state = groups;
  }
}

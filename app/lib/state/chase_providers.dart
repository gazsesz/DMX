import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/chase.dart';

const _uuid = Uuid();

final chasesProvider = StateNotifierProvider<ChasesNotifier, List<Chase>>((ref) {
  return ChasesNotifier();
});

class ChasesNotifier extends StateNotifier<List<Chase>> {
  ChasesNotifier() : super(const []);

  Chase create(String name) {
    final chase = Chase(id: _uuid.v4(), name: name, steps: const []);
    state = [...state, chase];
    return chase;
  }

  void upsert(Chase chase) {
    final exists = state.any((c) => c.id == chase.id);
    state = exists
        ? [for (final c in state) if (c.id == chase.id) chase else c]
        : [...state, chase];
  }

  void duplicate(String id) {
    final source = state.where((c) => c.id == id);
    if (source.isEmpty) return;
    final copy = source.first;
    state = [
      ...state,
      Chase(
        id: _uuid.v4(),
        name: '${copy.name} Copy',
        steps: copy.steps,
        stepSeconds: copy.stepSeconds,
        beatSync: copy.beatSync,
        direction: copy.direction,
      ),
    ];
  }

  void remove(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  void loadAll(List<Chase> chases) {
    state = chases;
  }
}

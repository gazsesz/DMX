import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/smart_program.dart';

const _uuid = Uuid();

final smartProgramsProvider = StateNotifierProvider<SmartProgramsNotifier, List<SmartProgram>>((ref) {
  return SmartProgramsNotifier();
});

class SmartProgramsNotifier extends StateNotifier<List<SmartProgram>> {
  SmartProgramsNotifier() : super(const []);

  SmartProgram create(String name) {
    final program = SmartProgram(id: _uuid.v4(), name: name);
    state = [...state, program];
    return program;
  }

  void upsert(SmartProgram program) {
    final exists = state.any((p) => p.id == program.id);
    state = exists
        ? [for (final p in state) if (p.id == program.id) program else p]
        : [...state, program];
  }

  void duplicate(String id) {
    final source = state.where((p) => p.id == id);
    if (source.isEmpty) return;
    final copy = source.first;
    state = [
      ...state,
      SmartProgram(
        id: _uuid.v4(),
        name: '${copy.name} Copy',
        baseChaseId: copy.baseChaseId,
        baseBpm: copy.baseBpm,
        thresholdMode: copy.thresholdMode,
        fasterChaseId: copy.fasterChaseId,
        fasterThreshold: copy.fasterThreshold,
        fasterHold: copy.fasterHold,
        slowerChaseId: copy.slowerChaseId,
        slowerThreshold: copy.slowerThreshold,
        slowerHold: copy.slowerHold,
      ),
    ];
  }

  void remove(String id) {
    state = state.where((p) => p.id != id).toList();
  }

  void loadAll(List<SmartProgram> programs) {
    state = programs;
  }
}

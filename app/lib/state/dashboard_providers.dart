import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard_trigger.dart';

final dashboardTriggersProvider =
    StateNotifierProvider<DashboardTriggersNotifier, List<DashboardTriggerRef>>((ref) {
      return DashboardTriggersNotifier();
    });

class DashboardTriggersNotifier extends StateNotifier<List<DashboardTriggerRef>> {
  DashboardTriggersNotifier() : super(const []);

  bool contains(String id, TriggerKind kind) {
    return state.any((t) => t.id == id && t.kind == kind);
  }

  void add(String id, TriggerKind kind) {
    if (contains(id, kind)) return;
    state = [...state, DashboardTriggerRef(id: id, kind: kind)];
  }

  void remove(String id, TriggerKind kind) {
    state = state.where((t) => !(t.id == id && t.kind == kind)).toList();
  }

  void toggle(String id, TriggerKind kind) {
    if (contains(id, kind)) {
      remove(id, kind);
    } else {
      add(id, kind);
    }
  }

  void loadAll(List<DashboardTriggerRef> refs) {
    state = refs;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard_prefs.dart';

const prefDashboardLayout = 'dashboard.layout';
const prefDashboardBoxSize = 'dashboard.boxSize';

class DashboardPrefsState {
  final TriggerLayout layout;
  final DashboardBoxSize boxSize;

  const DashboardPrefsState({this.layout = TriggerLayout.mosaic, this.boxSize = DashboardBoxSize.s});
}

/// How the Dashboard's Quick Triggers look — persisted the same way as the
/// Art-Net connection settings (loaded before the first frame in `main()`,
/// see there for why), so the layout/tile size choice survives app restarts
/// instead of always resetting to the default.
class DashboardPrefsNotifier extends StateNotifier<DashboardPrefsState> {
  DashboardPrefsNotifier(super.initial);

  void update(DashboardPrefsState Function(DashboardPrefsState current) updater) {
    state = updater(state);
    _persist(state);
  }

  Future<void> _persist(DashboardPrefsState prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(prefDashboardLayout, prefs.layout.name);
    await sp.setString(prefDashboardBoxSize, prefs.boxSize.name);
  }
}

final dashboardPrefsProvider = StateNotifierProvider<DashboardPrefsNotifier, DashboardPrefsState>((ref) {
  return DashboardPrefsNotifier(const DashboardPrefsState());
});

DashboardPrefsState dashboardPrefsFromStrings({String? layout, String? boxSize}) {
  return DashboardPrefsState(
    layout: TriggerLayout.values.firstWhere((e) => e.name == layout, orElse: () => TriggerLayout.mosaic),
    boxSize: DashboardBoxSize.values.firstWhere((e) => e.name == boxSize, orElse: () => DashboardBoxSize.s),
  );
}

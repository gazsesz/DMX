import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_data.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/project_providers.dart';
import '../../state/scene_providers.dart';

/// Gathers the whole show's current state into one [ProjectData] snapshot —
/// shared by the Files screen and the quick "Save Project" action available
/// from every main screen's app bar.
ProjectData buildProjectSnapshot(WidgetRef ref) {
  final library = ref.read(fixtureLibraryProvider);
  return ProjectData(
    name: ref.read(currentProjectNameProvider),
    settings: ref.read(artNetSettingsProvider),
    universes: ref.read(universesProvider),
    customFixtureProfiles: library.where((f) => !f.isBuiltIn).toList(),
    patchedFixtures: ref.read(patchedFixturesProvider),
    scenes: ref.read(scenesProvider),
    banks: ref.read(banksProvider),
    chases: ref.read(chasesProvider),
    dashboardTriggers: ref.read(dashboardTriggersProvider),
  );
}

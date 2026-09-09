import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project_data.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/project_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';

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
    smartPrograms: ref.read(smartProgramsProvider),
  );
}

/// The inverse of [buildProjectSnapshot] — pushes a loaded [ProjectData] into
/// every provider that holds a piece of it. Shared by the Files screen's
/// Load/Import actions and the startup auto-load of the most recently saved
/// project.
void applyProjectData(WidgetRef ref, ProjectData data) {
  ref.read(currentProjectNameProvider.notifier).state = data.name;
  ref.read(artNetSettingsProvider.notifier).update((_) => data.settings);
  ref.read(universesProvider.notifier).loadAll(data.universes);
  ref.read(fixtureLibraryProvider.notifier).loadAll(data.customFixtureProfiles);
  ref.read(patchedFixturesProvider.notifier).loadAll(data.patchedFixtures);
  ref.read(scenesProvider.notifier).loadAll(data.scenes);
  ref.read(banksProvider.notifier).loadAll(data.banks);
  ref.read(chasesProvider.notifier).loadAll(data.chases);
  ref.read(dashboardTriggersProvider.notifier).loadAll(data.dashboardTriggers);
  ref.read(smartProgramsProvider.notifier).loadAll(data.smartPrograms);
}

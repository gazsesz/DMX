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

/// How much of an existing show a new project starts from.
///
/// These are levels rather than independent checkboxes because the show
/// data is a dependency chain: scenes address patched fixtures, banks hold
/// scenes, chases step through banks, and the Dashboard points at chases.
/// Carrying banks over without their fixtures would just produce a project
/// full of references to things that aren't there.
enum ProjectCarryOver {
  /// Nothing — a blank show, the way "New Project" always behaved.
  empty,

  /// The rig: universes, custom fixture profiles and the patch. The usual
  /// choice — the venue hasn't changed, the show has.
  fixtures,

  /// A full copy: the rig plus every scene, bank, chase, Dashboard tile and
  /// smart program, under a new name.
  everything;

  String get label => switch (this) {
    ProjectCarryOver.empty => 'Empty project',
    ProjectCarryOver.fixtures => 'Keep fixtures',
    ProjectCarryOver.everything => 'Full copy',
  };

  String get description => switch (this) {
    ProjectCarryOver.empty => 'Start from nothing — no fixtures, scenes, banks or chases',
    ProjectCarryOver.fixtures => 'Universes, fixture profiles and the patch carry over; scenes, banks and chases start empty',
    ProjectCarryOver.everything => 'Everything carries over, saved under the new name',
  };
}

/// Starts a project called [name] from [source], keeping as much of it as
/// [carryOver] asks for.
///
/// The Art-Net connection settings are deliberately left alone in every
/// mode: they describe the node on the desk, not the show, and the app
/// already persists them separately from any project file.
void startProject(
  WidgetRef ref, {
  required String name,
  required ProjectCarryOver carryOver,
  required ProjectData source,
}) {
  if (carryOver == ProjectCarryOver.everything) {
    applyProjectData(ref, ProjectData(
      name: name,
      settings: ref.read(artNetSettingsProvider),
      universes: source.universes,
      customFixtureProfiles: source.customFixtureProfiles,
      patchedFixtures: source.patchedFixtures,
      scenes: source.scenes,
      banks: source.banks,
      chases: source.chases,
      dashboardTriggers: source.dashboardTriggers,
      smartPrograms: source.smartPrograms,
    ));
    return;
  }

  final keepRig = carryOver == ProjectCarryOver.fixtures;
  ref.read(currentProjectNameProvider.notifier).state = name;
  if (keepRig) {
    ref.read(universesProvider.notifier).loadAll(source.universes);
    ref.read(fixtureLibraryProvider.notifier).loadAll(source.customFixtureProfiles);
    ref.read(patchedFixturesProvider.notifier).loadAll(source.patchedFixtures);
  } else {
    ref.read(universesProvider.notifier).reset();
    ref.read(fixtureLibraryProvider.notifier).loadAll(const []);
    ref.read(patchedFixturesProvider.notifier).loadAll(const []);
  }
  ref.read(scenesProvider.notifier).loadAll(const []);
  ref.read(banksProvider.notifier).reset();
  ref.read(chasesProvider.notifier).loadAll(const []);
  ref.read(dashboardTriggersProvider.notifier).loadAll(const []);
  ref.read(smartProgramsProvider.notifier).loadAll(const []);
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

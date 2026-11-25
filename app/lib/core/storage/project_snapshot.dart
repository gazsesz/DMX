import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/midi_mapping.dart';
import '../../models/project_data.dart';
import '../../models/stage_plan.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/autosave_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/dimmer_dropout_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/live_providers.dart';
import '../../state/midi_control_providers.dart';
import '../../state/project_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/song_show_providers.dart';
import '../../state/stage_providers.dart';

/// Gathers the whole show's current state into one [ProjectData] snapshot —
/// shared by the Files screen and the quick "Save Project" action available
/// from every main screen's app bar.
ProjectData buildProjectSnapshot(WidgetRef ref) => projectSnapshotOf(ref.read);

/// Reads any provider — `ref.read` of a [WidgetRef] or a provider's [Ref].
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// [buildProjectSnapshot] for code that has no widget: the autosaver.
ProjectData projectSnapshotOf(ProviderReader read) {
  final library = read(fixtureLibraryProvider);
  return ProjectData(
    name: read(currentProjectNameProvider),
    settings: read(artNetSettingsProvider),
    universes: read(universesProvider),
    customFixtureProfiles: library.where((f) => !f.isBuiltIn).toList(),
    patchedFixtures: read(patchedFixturesProvider),
    fixtureGroups: read(fixtureGroupsProvider),
    scenes: read(scenesProvider),
    banks: read(banksProvider),
    chases: read(chasesProvider),
    dashboardTriggers: read(dashboardTriggersProvider),
    smartPrograms: read(smartProgramsProvider),
    songShows: read(songShowsProvider),
    layers: read(layersProvider),
    stagePlan: read(stagePlanProvider),
    positionPresets: read(positionPresetsProvider),
    lastSelectedBankId: read(selectedBankIdProvider),
    dimmerDropout: read(dimmerDropoutProvider),
    midiMappings: read(midiMappingsProvider),
    liveGrid: read(liveGridProvider),
    beatTuning: read(beatTuningProvider),
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
      fixtureGroups: source.fixtureGroups,
      scenes: source.scenes,
      banks: source.banks,
      chases: source.chases,
      dashboardTriggers: source.dashboardTriggers,
      smartPrograms: source.smartPrograms,
      songShows: source.songShows,
      layers: source.layers,
      stagePlan: source.stagePlan,
      positionPresets: source.positionPresets,
      lastSelectedBankId: source.lastSelectedBankId,
      dimmerDropout: source.dimmerDropout,
      midiMappings: source.midiMappings,
      liveGrid: source.liveGrid,
      beatTuning: source.beatTuning,
    ));
    // A new name that isn't on disk yet — unlike a loaded file.
    ref.read(projectAutoSaveProvider.notifier).markChanged();
    return;
  }

  final keepRig = carryOver == ProjectCarryOver.fixtures;
  ref.read(currentProjectNameProvider.notifier).state = name;
  if (keepRig) {
    ref.read(universesProvider.notifier).loadAll(source.universes);
    ref.read(fixtureLibraryProvider.notifier).loadAll(source.customFixtureProfiles);
    ref.read(patchedFixturesProvider.notifier).loadAll(source.patchedFixtures);
    ref.read(fixtureGroupsProvider.notifier).loadAll(source.fixtureGroups);
    // The stage and the saved positions describe the rig, not the show.
    ref.read(stagePlanProvider.notifier).load(source.stagePlan);
    ref.read(positionPresetsProvider.notifier).loadAll(source.positionPresets);
    // The lanes point at this rig's groups, so the grid carries over with it.
    ref.read(liveGridProvider.notifier).load(source.liveGrid);
  } else {
    ref.read(universesProvider.notifier).reset();
    ref.read(fixtureLibraryProvider.notifier).loadAll(const []);
    ref.read(patchedFixturesProvider.notifier).loadAll(const []);
    ref.read(fixtureGroupsProvider.notifier).loadAll(const []);
    ref.read(stagePlanProvider.notifier).load(const StagePlan());
    ref.read(positionPresetsProvider.notifier).loadAll(const []);
    ref.read(liveGridProvider.notifier).load(null);
  }
  ref.read(scenesProvider.notifier).loadAll(const []);
  ref.read(banksProvider.notifier).reset();
  ref.read(chasesProvider.notifier).loadAll(const []);
  ref.read(dashboardTriggersProvider.notifier).loadAll(const []);
  ref.read(smartProgramsProvider.notifier).loadAll(const []);
  ref.read(songShowsProvider.notifier).loadAll(const []);
  ref.read(layersProvider.notifier).reset();
  ref.read(dimmerDropoutProvider.notifier).update(const DropoutSettings());
  ref.read(selectedBankIdProvider.notifier).state = null;
  // The controller's pads that start banks and chases point at things that
  // are gone now; the rest (blackout, master, colours…) still mean the same.
  ref.read(midiMappingsProvider.notifier).loadAll([
    for (final m in source.midiMappings)
      if (m.action != MidiActionKind.playTarget && (keepRig || !m.action.isLiveGrid)) m,
  ]);
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
  ref.read(fixtureGroupsProvider.notifier).loadAll(data.fixtureGroups);
  ref.read(stagePlanProvider.notifier).load(data.stagePlan);
  ref.read(positionPresetsProvider.notifier).loadAll(data.positionPresets);
  ref.read(scenesProvider.notifier).loadAll(data.scenes);
  ref.read(banksProvider.notifier).loadAll(data.banks);
  ref.read(chasesProvider.notifier).loadAll(data.chases);
  ref.read(dashboardTriggersProvider.notifier).loadAll(data.dashboardTriggers);
  ref.read(smartProgramsProvider.notifier).loadAll(data.smartPrograms);
  ref.read(songShowsProvider.notifier).loadAll(data.songShows);
  ref.read(layersProvider.notifier).loadAll(data.layers);
  ref.read(dimmerDropoutProvider.notifier).update(data.dimmerDropout);
  ref.read(selectedBankIdProvider.notifier).state = data.lastSelectedBankId;
  ref.read(midiMappingsProvider.notifier).loadAll(data.midiMappings);
  ref.read(liveGridProvider.notifier).load(data.liveGrid);
  ref.read(beatTuningProvider.notifier).load(data.beatTuning);
  // What's open now is exactly what's on disk.
  ref.read(projectAutoSaveProvider.notifier).markSaved();
}

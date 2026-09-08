import 'artnet_settings.dart';
import 'bank.dart';
import 'chase.dart';
import 'dashboard_trigger.dart';
import 'fixture_profile.dart';
import 'patched_fixture.dart';
import 'scene.dart';
import 'universe_config.dart';

/// Everything that makes up one show file.
class ProjectData {
  final String name;
  final ArtNetSettings settings;
  final List<UniverseConfig> universes;
  final List<FixtureProfile> customFixtureProfiles;
  final List<PatchedFixture> patchedFixtures;
  final List<Scene> scenes;
  final List<Bank> banks;
  final List<Chase> chases;
  final List<DashboardTriggerRef> dashboardTriggers;

  const ProjectData({
    required this.name,
    required this.settings,
    required this.universes,
    required this.customFixtureProfiles,
    required this.patchedFixtures,
    required this.scenes,
    required this.banks,
    required this.chases,
    this.dashboardTriggers = const [],
  });

  Map<String, dynamic> toJson() => {
    'formatVersion': 1,
    'name': name,
    'settings': settings.toJson(),
    'universes': universes.map((u) => u.toJson()).toList(),
    'fixtureProfiles': customFixtureProfiles.map((f) => f.toJson()).toList(),
    'patchedFixtures': patchedFixtures.map((p) => p.toJson()).toList(),
    'scenes': scenes.map((s) => s.toJson()).toList(),
    'banks': banks.map((b) => b.toJson()).toList(),
    'chases': chases.map((c) => c.toJson()).toList(),
    'dashboardTriggers': dashboardTriggers.map((t) => t.toJson()).toList(),
  };

  factory ProjectData.fromJson(Map<String, dynamic> json, {required List<FixtureProfile> builtIns}) {
    final customProfiles = (json['fixtureProfiles'] as List? ?? [])
        .map((f) => FixtureProfile.fromJson(f as Map<String, dynamic>))
        .toList();
    final library = [...builtIns, ...customProfiles];
    return ProjectData(
      name: json['name'] as String? ?? 'Untitled',
      settings: ArtNetSettings.fromJson(json['settings'] as Map<String, dynamic>? ?? {}),
      universes: (json['universes'] as List? ?? [])
          .map((u) => UniverseConfig.fromJson(u as Map<String, dynamic>))
          .toList(),
      customFixtureProfiles: customProfiles,
      patchedFixtures: (json['patchedFixtures'] as List? ?? [])
          .map((p) => PatchedFixture.fromJson(p as Map<String, dynamic>, library))
          .toList(),
      scenes: (json['scenes'] as List? ?? []).map((s) => Scene.fromJson(s as Map<String, dynamic>)).toList(),
      banks: (json['banks'] as List? ?? []).map((b) => Bank.fromJson(b as Map<String, dynamic>)).toList(),
      chases: (json['chases'] as List? ?? []).map((c) => Chase.fromJson(c as Map<String, dynamic>)).toList(),
      dashboardTriggers: (json['dashboardTriggers'] as List? ?? [])
          .map((t) => DashboardTriggerRef.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

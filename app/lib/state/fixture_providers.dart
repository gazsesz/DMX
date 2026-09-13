import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/fixtures/fixture_library_asset.dart';
import '../models/builtin_fixtures.dart';
import '../models/channel_capability.dart';
import '../models/channel_function.dart';
import '../models/fixture_channel.dart';
import '../models/fixture_profile.dart';
import '../models/patched_fixture.dart';

const _uuid = Uuid();

/// The read-only fixture library bundled with the app. One instance, so the
/// manufacturer index and any manufacturer file already opened stay parsed.
final fixtureLibraryAssetProvider = Provider<FixtureLibraryAsset>((ref) => FixtureLibraryAsset());

/// Built-in templates plus any custom fixtures the user has created.
final fixtureLibraryProvider =
    StateNotifierProvider<FixtureLibraryNotifier, List<FixtureProfile>>((ref) {
      return FixtureLibraryNotifier();
    });

class FixtureLibraryNotifier extends StateNotifier<List<FixtureProfile>> {
  FixtureLibraryNotifier() : super(List.unmodifiable(builtInFixtureProfiles));

  FixtureProfile addCustom({
    required String name,
    required FixtureCategory category,
    required List<FixtureChannelDraft> channels,
    String? manufacturer,
    String? model,
    String? modeName,
    String? sourceFormat,
  }) {
    final profile = FixtureProfile(
      id: _uuid.v4(),
      name: name,
      category: category,
      channels: [
        for (var i = 0; i < channels.length; i++)
          channels[i].toChannel(i),
      ],
      manufacturer: manufacturer,
      model: model,
      modeName: modeName,
      sourceFormat: sourceFormat,
    );
    state = [...state, profile];
    return profile;
  }

  /// Adds an already-built profile (an import, or a pick from the bundled
  /// library) under a fresh id, so the same library entry can be brought in
  /// twice and edited independently.
  FixtureProfile addProfile(FixtureProfile profile) {
    final copy = FixtureProfile(
      id: _uuid.v4(),
      name: profile.name,
      category: profile.category,
      channels: profile.channels,
      manufacturer: profile.manufacturer,
      model: profile.model,
      modeName: profile.modeName,
      sourceFormat: profile.sourceFormat,
    );
    state = [...state, copy];
    return copy;
  }

  FixtureProfile updateCustom(
    String id, {
    required String name,
    required FixtureCategory category,
    required List<FixtureChannelDraft> channels,
  }) {
    // Keep the import provenance across an edit — the user renaming a
    // channel shouldn't erase which library entry this came from.
    final existing = state.where((p) => p.id == id).firstOrNull;
    final updated = FixtureProfile(
      id: id,
      name: name,
      category: category,
      channels: [for (var i = 0; i < channels.length; i++) channels[i].toChannel(i)],
      manufacturer: existing?.manufacturer,
      model: existing?.model,
      modeName: existing?.modeName,
      sourceFormat: existing?.sourceFormat,
    );
    state = [for (final p in state) if (p.id == id) updated else p];
    return updated;
  }

  void removeCustom(String id) {
    state = state.where((p) => p.id != id || p.isBuiltIn).toList();
  }

  void loadAll(List<FixtureProfile> customProfiles) {
    state = [...builtInFixtureProfiles, ...customProfiles];
  }
}

/// Working draft for the fixture editor's channel table, before a profile
/// exists (so rows can be reordered/added/removed freely).
class FixtureChannelDraft {
  ChannelFunction function;
  String? customLabel;
  List<ChannelCapability> capabilities;

  FixtureChannelDraft({
    required this.function,
    this.customLabel,
    List<ChannelCapability>? capabilities,
  }) : capabilities = [...?capabilities];

  FixtureChannel toChannel(int offset) => FixtureChannel(
    offset: offset,
    function: function,
    customLabel: customLabel,
    capabilities: normalizeCapabilities(capabilities),
  );
}

final patchedFixturesProvider =
    StateNotifierProvider<PatchedFixturesNotifier, List<PatchedFixture>>((ref) {
      return PatchedFixturesNotifier();
    });

class PatchedFixturesNotifier extends StateNotifier<List<PatchedFixture>> {
  PatchedFixturesNotifier() : super(const []);

  PatchedFixture patch({
    required String label,
    required FixtureProfile profile,
    required String universeId,
    required int startChannel,
  }) {
    final fixture = PatchedFixture(
      id: _uuid.v4(),
      label: label,
      profile: profile,
      universeId: universeId,
      startChannel: startChannel,
    );
    state = [...state, fixture];
    return fixture;
  }

  void duplicate(String id) {
    final source = state.where((f) => f.id == id).firstOrNull;
    if (source == null) return;
    final maxEnd = state
        .where((f) => f.universeId == source.universeId)
        .map((f) => f.startChannel + f.profile.channelCount)
        .fold(0, (a, b) => a > b ? a : b);
    state = [
      ...state,
      PatchedFixture(
        id: _uuid.v4(),
        label: '${source.label} Copy',
        profile: source.profile,
        universeId: source.universeId,
        startChannel: maxEnd.clamp(0, 511),
      ),
    ];
  }

  void update(String id, PatchedFixture Function(PatchedFixture current) updater) {
    state = [
      for (final fixture in state)
        if (fixture.id == id) updater(fixture) else fixture,
    ];
  }

  void remove(String id) {
    state = state.where((f) => f.id != id).toList();
  }

  /// Re-points every fixture patched from [profile] to the new (edited)
  /// version of that same profile, so channel remaps take effect live.
  void refreshProfile(FixtureProfile profile) {
    state = [
      for (final fixture in state)
        if (fixture.profile.id == profile.id) fixture.withProfile(profile) else fixture,
    ];
  }

  void setLayoutPosition(String id, double x, double y) {
    state = [
      for (final fixture in state)
        if (fixture.id == id) fixture.copyWith(layoutX: x.clamp(0.0, 1.0), layoutY: y.clamp(0.0, 1.0)) else fixture,
    ];
  }

  void loadAll(List<PatchedFixture> fixtures) {
    state = fixtures;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

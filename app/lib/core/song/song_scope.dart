import '../../models/fixture_group.dart';
import '../../models/patched_fixture.dart';

/// The DMX channels (universe id → channel numbers) of the fixtures in the
/// groups [groupIds]; null when that means "everything" — no groups chosen,
/// or none of them still exist / hold a patched fixture (so a deleted group
/// never silences the show).
Map<String, Set<int>>? scopeChannels({
  required List<String> groupIds,
  required List<FixtureGroup> groups,
  required List<PatchedFixture> fixtures,
}) {
  if (groupIds.isEmpty) return null;
  final fixtureIds = {
    for (final g in groups)
      if (groupIds.contains(g.id)) ...g.fixtureIds,
  };
  final channels = <String, Set<int>>{};
  for (final f in fixtures) {
    if (!fixtureIds.contains(f.id)) continue;
    final set = channels.putIfAbsent(f.universeId, () => <int>{});
    for (var i = 0; i < f.profile.channelCount; i++) {
      set.add(f.startChannel + i);
    }
  }
  return channels.isEmpty ? null : channels;
}

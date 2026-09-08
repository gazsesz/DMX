import '../../models/patched_fixture.dart';
import '../../models/scene.dart';
import '../../models/universe_config.dart';
import '../artnet/artnet_service.dart';

/// Writes a scene's stored channel values out to the real DMX universes via
/// [service], resolving each patched fixture's start channel + universe.
void outputScene({
  required ArtNetService service,
  required Scene scene,
  required List<PatchedFixture> patchedFixtures,
  required List<UniverseConfig> universes,
}) {
  final touched = <UniverseConfig>{};
  for (final entry in scene.fixtureValues.entries) {
    final matches = patchedFixtures.where((f) => f.id == entry.key);
    if (matches.isEmpty) continue;
    final patched = matches.first;
    final universeMatches = universes.where((u) => u.id == patched.universeId);
    if (universeMatches.isEmpty) continue;
    final universe = universeMatches.first;
    final values = entry.value;
    for (var i = 0; i < values.length; i++) {
      service.setChannel(universe, patched.startChannel + i, values[i], send: false);
    }
    touched.add(universe);
  }
  // One packet per affected universe, not one per changed channel.
  for (final universe in touched) {
    service.flush(universe);
  }
}

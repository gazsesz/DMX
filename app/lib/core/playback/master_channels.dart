import '../../models/patched_fixture.dart';
import '../../models/universe_config.dart';

/// Which DMX channels the grand master is allowed to scale, per universe id.
///
/// Not all of them, and that's the whole point. Scaling pan would swing a
/// moving head across the stage as you pull the master down; scaling a gobo
/// channel would change the pattern; scaling a strobe channel would change
/// its rate. The master means "less light", so it touches intensity only.
///
/// For a fixture with a dimmer channel that's the dimmer. For one without —
/// most cheap RGB pars — the colour emitters *are* the intensity, so those
/// get scaled instead, which keeps the hue and just takes it down.
Map<String, Set<int>> masterChannelsFor(
  List<PatchedFixture> fixtures,
  List<UniverseConfig> universes,
) {
  final known = {for (final universe in universes) universe.id};
  final result = <String, Set<int>>{};

  for (final fixture in fixtures) {
    if (!known.contains(fixture.universeId)) continue;
    final channels = fixture.profile.channels;
    final dimmers = [for (final c in channels) if (c.function.isDimmer) c.offset];
    final offsets = dimmers.isNotEmpty
        ? dimmers
        : [for (final c in channels) if (c.function.isColorMix) c.offset];

    final target = result.putIfAbsent(fixture.universeId, () => <int>{});
    for (final offset in offsets) {
      final channel = fixture.startChannel + offset;
      if (channel >= 0 && channel <= 511) target.add(channel);
    }
  }
  return result;
}

import 'dart:typed_data';

import '../../models/patched_fixture.dart';
import '../../models/universe_config.dart';

/// The momentary effects the dock's hold buttons lay over the running show.
///
/// All three are *output* effects: they change the frame on its way to the
/// node and never touch the channel buffers the show writes into. Letting go
/// therefore puts the previous look back exactly — including whatever the
/// chase stepped on to while you were holding, because underneath it never
/// stopped playing.
enum MomentaryFx {
  /// Chops what's on stage: the look, gated hard on and off at the strobe
  /// rate. Fades have no say in it — a strobe that fades isn't a strobe.
  ///
  /// It gates rather than firing its own white flash so the colours you
  /// programmed keep strobing; hold [blinder] with it for a white one.
  strobe,

  /// Everything up and white: dimmers and colour emitters to full, over the
  /// top of whatever is playing.
  blinder,

  /// Holds the output where it is. The show carries on underneath, so
  /// letting go rejoins it live rather than rewinding to where it froze.
  freeze;

  String get label => switch (this) {
    MomentaryFx.strobe => 'Strobe',
    MomentaryFx.blinder => 'Blinder',
    MomentaryFx.freeze => 'Freeze',
  };
}

/// Which channels the blinder drives to full, per universe id.
///
/// Dimmers *and* colour emitters, unlike `masterChannelsFor`, which picks
/// one or the other: the master means "less light" and has to leave the
/// colour alone, while a blinder means everything up and white — so a wash
/// with a dimmer gets its dimmer opened *and* its colours run up, instead of
/// its programmed colour taken to full.
///
/// Shutters are left where the show set them. There is no value that means
/// "open" on every fixture, and a guess would shut one that was already open.
Map<String, Set<int>> blinderChannelsFor(
  List<PatchedFixture> fixtures,
  List<UniverseConfig> universes,
) {
  final known = {for (final universe in universes) universe.id};
  final result = <String, Set<int>>{};

  for (final fixture in fixtures) {
    if (!known.contains(fixture.universeId)) continue;
    final target = result.putIfAbsent(fixture.universeId, () => <int>{});
    for (final channel in fixture.profile.channels) {
      if (!channel.function.isDimmer && !channel.function.isColorMix) continue;
      final address = fixture.startChannel + channel.offset;
      if (address >= 0 && address <= 511) target.add(address);
    }
  }
  return result;
}

/// One universe's frame as it should leave the device while [held] is down.
///
/// The three compose, and the order is what makes the combinations you'd
/// actually grab work: [MomentaryFx.freeze] decides *which* frame is being
/// looked at, [MomentaryFx.blinder] lifts that frame to full, and
/// [MomentaryFx.strobe] chops whatever the other two left. Holding strobe
/// and blinder together is a white strobe; holding strobe and freeze chops a
/// still.
///
/// [lit] is the strobe's phase — true while the flash is on. [frozen] is the
/// frame the freeze started from, and [intensityChannels] is the same set the
/// grand master scales (`masterChannelsFor`), so the strobe takes light away
/// exactly where the master would and never chops a pan or a gobo.
///
/// Returns [frame] itself when there is nothing to change, so the normal case
/// allocates nothing. Never writes into [frame] or [frozen].
Uint8List applyMomentaryFx({
  required Uint8List frame,
  required Set<MomentaryFx> held,
  required bool lit,
  Uint8List? frozen,
  Set<int> blinderChannels = const {},
  Set<int> intensityChannels = const {},
}) {
  final base = held.contains(MomentaryFx.freeze) && frozen != null ? frozen : frame;
  final blind = held.contains(MomentaryFx.blinder);
  final chopped = held.contains(MomentaryFx.strobe) && !lit;
  if (!blind && !chopped) return base;

  final out = Uint8List.fromList(base);
  if (blind) {
    for (final channel in blinderChannels) {
      if (channel >= 0 && channel < out.length) out[channel] = 255;
    }
  }
  // Last, and after the blinder on purpose: the dark half of a strobe is
  // dark whatever else is being held.
  if (chopped) {
    for (final channel in intensityChannels) {
      if (channel >= 0 && channel < out.length) out[channel] = 0;
    }
  }
  return out;
}

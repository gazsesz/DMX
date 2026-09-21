import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/artnet/artnet_service.dart';
import '../core/playback/master_channels.dart';
import '../core/playback/momentary_fx.dart';
import '../models/universe_config.dart';
import 'artnet_providers.dart';
import 'audio_providers.dart';
import 'fixture_providers.dart';

export '../core/playback/momentary_fx.dart' show MomentaryFx;

/// How fast the strobe chops, in flashes per second.
///
/// 12 is about where a chop stops reading as a very fast chase and starts
/// reading as a strobe. The range is what a real strobe covers: 1 is a pulse
/// you can count, and past 25 you're asking for more frames a second than DMX
/// has to give.
final strobeRateProvider = StateProvider<double>((ref) => 12);

const minStrobeHz = 1.0;
const maxStrobeHz = 25.0;

/// Which momentary effects are being held right now — empty almost always,
/// because these live exactly as long as a finger is on the button.
///
/// One controller app-wide, like the players: the dock draws these buttons in
/// more than one place at a time (the closed strip and the open panel's rail)
/// and both have to be holding the *same* effect rather than one each.
final momentaryFxProvider = StateNotifierProvider<MomentaryFxController, Set<MomentaryFx>>((ref) {
  return MomentaryFxController(ref);
});

/// Drives the momentary effects: what's held, the strobe's phase, and the
/// frame a freeze is holding on to.
///
/// Nothing here stops playback. A held effect is a layer applied on the way
/// out (see [ArtNetService.outputOverride]) and the show keeps stepping
/// underneath it, so releasing doesn't have to put anything back by hand —
/// the very next frame out is the live one again.
class MomentaryFxController extends StateNotifier<Set<MomentaryFx>> {
  final Ref _ref;

  /// The frame each universe was on when the freeze went down.
  final Map<String, Uint8List> _frozen = {};

  /// Worked out when a button goes down rather than kept in step with the
  /// patch: a hold lasts seconds, and nobody re-patches mid-hold.
  Map<String, Set<int>> _blinderChannels = const {};
  Map<String, Set<int>> _intensityChannels = const {};

  /// The strobe's phase — true while the flash is lit. Left true whenever no
  /// strobe is held, so the layer never darkens anything on its own.
  bool _lit = true;
  Timer? _strobeTimer;
  StreamSubscription<DateTime>? _beatSub;

  MomentaryFxController(this._ref) : super(const {});

  ArtNetService get _service => _ref.read(artNetServiceProvider);

  bool isHeld(MomentaryFx fx) => state.contains(fx);

  /// Button down.
  void press(MomentaryFx fx) {
    if (state.contains(fx)) return;
    final universes = _ref.read(universesProvider);
    final fixtures = _ref.read(patchedFixturesProvider);
    _blinderChannels = blinderChannelsFor(fixtures, universes);
    _intensityChannels = masterChannelsFor(fixtures, universes);
    if (fx == MomentaryFx.freeze) {
      for (final universe in universes) {
        _frozen[universe.id] = _service.snapshotFrame(universe);
      }
    }
    if (fx == MomentaryFx.strobe) _startStrobe();
    state = {...state, fx};
    // Setting the layer re-sends every universe, so the effect lands on the
    // rig now rather than whenever the show next writes a frame.
    _service.outputOverride = _layer;
  }

  /// Button up — or the finger sliding off it, or the button being taken off
  /// screen mid-hold. All three have to end the effect: one nobody is holding
  /// any more is one nobody can stop.
  void release(MomentaryFx fx) {
    if (!state.contains(fx)) return;
    state = {
      for (final held in state)
        if (held != fx) held,
    };
    if (fx == MomentaryFx.freeze) _frozen.clear();
    if (fx == MomentaryFx.strobe) _stopStrobe();
    if (state.isEmpty) {
      // Clearing the layer re-sends everything, and that *is* the restore:
      // the buffers still hold the look the show has been playing all along.
      _service.outputOverride = null;
    } else {
      _service.refreshOutput();
    }
  }

  /// [release], but on the next microtask.
  ///
  /// For the one caller that can't do it there and then: a button being
  /// disposed with a finger still on it. Riverpod refuses a provider change
  /// from inside a widget life-cycle, and dispose is one — so the effect ends
  /// a microtask later, still long before the next frame leaves.
  void releaseLater(MomentaryFx fx) {
    Future.microtask(() {
      if (mounted) release(fx);
    });
  }

  /// Ends every held effect. Blackout calls this first: the panic button has
  /// to win, and a held freeze would otherwise keep pushing its frame out
  /// over the top of the blackout.
  void releaseAll() {
    for (final fx in state.toList()) {
      release(fx);
    }
  }

  Uint8List _layer(UniverseConfig universe, Uint8List frame) => applyMomentaryFx(
    frame: frame,
    held: state,
    lit: _lit,
    frozen: _frozen[universe.id],
    blinderChannels: _blinderChannels[universe.id] ?? const {},
    intensityChannels: _intensityChannels[universe.id] ?? const {},
  );

  /// The lit and dark halves of one strobe cycle, at a 40% duty cycle — a
  /// stab reads as a stab, where an even square wave reads as a fast chase.
  Duration get _onTime => _phase(0.4);

  Duration get _offTime => _phase(0.6);

  Duration _phase(double share) {
    final hz = _ref.read(strobeRateProvider).clamp(minStrobeHz, maxStrobeHz);
    // The floor is there for the same reason a chase step has one: a phase
    // shorter than a frame is packets the node can do nothing with.
    return Duration(milliseconds: (1000 * share / hz).round().clamp(15, 2000));
  }

  void _startStrobe() {
    _lit = true;
    _scheduleFlip();
    // Beats re-align the phase, they don't set the rate. That's the Flash
    // beat rate's trick — lit *on* the beat, for a fixed short time — laid
    // over a chop that free-runs on its own, so the strobe locks to the music
    // when there is music and carries on when the detector loses it. A strobe
    // that stops with the song is one that fails you mid-song.
    if (_ref.read(beatSyncEnabledProvider)) {
      _beatSub = _ref.read(activeBeatSourceProvider).beatEvents.listen((_) {
        if (!state.contains(MomentaryFx.strobe)) return;
        _lit = true;
        _service.refreshOutput();
        _scheduleFlip();
      });
    }
  }

  void _scheduleFlip() {
    _strobeTimer?.cancel();
    _strobeTimer = Timer(_lit ? _onTime : _offTime, () {
      _lit = !_lit;
      _service.refreshOutput();
      _scheduleFlip();
    });
  }

  void _stopStrobe() {
    _strobeTimer?.cancel();
    _strobeTimer = null;
    _beatSub?.cancel();
    _beatSub = null;
    _lit = true;
  }

  @override
  void dispose() {
    _stopStrobe();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/local_address.dart';
import 'artnet_providers.dart';
import 'audio_providers.dart';

/// This tablet's current Wi-Fi/LAN address, kept live — see
/// [watchLocalAddress]. Null while there is no usable network.
final localAddressProvider = StreamProvider<String?>((ref) => watchLocalAddress());

/// Re-opens what a network switch leaves pointing at the old Wi-Fi.
///
/// Watched once from the app shell so it lives for the whole session. The
/// first address seen is the starting point, not a change; losing the
/// network (null) is waited out, and the next real address is what counts.
final networkChangeWatcherProvider = Provider<void>((ref) {
  var seen = false;
  String? previous;
  ref.listen<AsyncValue<String?>>(localAddressProvider, (_, next) {
    if (!next.hasValue) return;
    final address = next.value;
    if (address == null) return;
    if (!seen) {
      seen = true;
      previous = address;
      return;
    }
    if (address == previous) return;
    previous = address;
    // The Art-Net/sACN socket: rebind now rather than waiting for the
    // watchdog's two missed polls (up to 20 s of a dark rig).
    unawaited(ref.read(connectionStatusProvider.notifier).onNetworkChanged());
    // rkbx_link's OSC listener, if it's the one in use.
    final osc = ref.read(oscBeatSourceProvider);
    if (osc.isListening) unawaited(osc.stop().then((_) => osc.start()));
  }, fireImmediately: true);
});

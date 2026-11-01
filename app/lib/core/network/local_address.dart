import 'dart:async';
import 'dart:io';

/// One network interface as far as picking "this tablet's address" goes —
/// a plain record so the choice can be tested without real interfaces.
typedef InterfaceAddresses = ({String name, List<String> ipv4});

/// Interface names that are never the Wi-Fi a lighting rig sits on: mobile
/// data (`rmnet`, `ccmni`, `pdp`), VPN tunnels, Wi-Fi Direct and the like.
final _notWifi = RegExp(r'^(rmnet|ccmni|pdp|v4-rmnet|tun|ppp|p2p|dummy|ip6tnl|sit|lo|r_rmnet|clat)', caseSensitive: false);

/// Names a Wi-Fi or wired LAN interface goes by on Android, Linux, Windows
/// and macOS.
final _lan = RegExp(r'^(wlan|wifi|wl|swlan|en|eth|wi-fi|ethernet)', caseSensitive: false);

/// Picks the address a remote, rkbx_link or the Wear OS app should be
/// pointed at, or null when there is none.
///
/// The old pick was simply "the first non-loopback IPv4", which on a phone
/// can be the mobile-data interface, and a link-local 169.254.x.x is never
/// reachable from another device. A Wi-Fi/LAN-named interface wins; then
/// anything that isn't plainly mobile data or a tunnel.
String? pickLocalAddress(List<InterfaceAddresses> interfaces) {
  bool usable(String ip) => !ip.startsWith('127.') && !ip.startsWith('169.254.') && ip != '0.0.0.0';
  String? firstIn(Iterable<InterfaceAddresses> list) {
    for (final interface in list) {
      for (final ip in interface.ipv4) {
        if (usable(ip)) return ip;
      }
    }
    return null;
  }

  return firstIn(interfaces.where((i) => _lan.hasMatch(i.name))) ??
      firstIn(interfaces.where((i) => !_notWifi.hasMatch(i.name)));
}

/// The Wi-Fi address to point a macro at, or null if there's no usable one.
Future<String?> localWifiAddress() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    return pickLocalAddress([
      for (final i in interfaces) (name: i.name, ipv4: [for (final a in i.addresses) a.address]),
    ]);
  } catch (_) {
    // No network yet — the Settings screen just shows nothing.
    return null;
  }
}

/// Watches [localWifiAddress] and reports every change — joining another
/// Wi-Fi hands the tablet a new address, and everything that told someone
/// "point it here" (the Setup screen's remote URL and rkbx_link line) and
/// every socket that should be re-opened on the new network needs to know.
///
/// Polls, because Dart has no network-change event and a plugin for one
/// would be a new native dependency for a check this cheap: listing the
/// interfaces is a single syscall. Emits the current address first.
Stream<String?> watchLocalAddress({
  Duration every = const Duration(seconds: 3),
  Future<String?> Function() read = localWifiAddress,
}) {
  late StreamController<String?> controller;
  Timer? timer;
  String? last;
  var first = true;

  // A one-shot timer re-armed after each read, rather than a periodic one:
  // reads never overlap, and nothing is left scheduled while a read is
  // still out (which also keeps widget tests, where real I/O never
  // completes, free of a pending timer).
  Future<void> check() async {
    final address = await read();
    if (controller.isClosed || !controller.hasListener) return;
    if (first || address != last) {
      first = false;
      last = address;
      controller.add(address);
    }
    timer = Timer(every, () => unawaited(check()));
  }

  controller = StreamController<String?>(
    onListen: () => unawaited(check()),
    onCancel: () {
      timer?.cancel();
      timer = null;
      controller.close();
    },
  );
  return controller.stream;
}

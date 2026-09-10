import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../state/playback_providers.dart';
import 'trigger_actions.dart';

/// A tiny HTTP endpoint for firing triggers from outside the app — a phone,
/// a smartwatch running MacroDroid, a laptop, anything on the same Wi-Fi as
/// the tablet.
///
/// It deliberately answers to the *names* shown in the app rather than screen
/// positions: renaming or reordering tiles is then the only thing that can
/// break a macro, and it fails loudly with a message instead of tapping the
/// wrong thing.
///
/// Endpoints (all plain GET, so they work from a browser or a one-line macro):
///   /            — what's running plus every name it answers to
///   /trigger?name=Front%20Wash — start it, or stop it if it's the one running
///   /stop        — stop playback, leaving the rig as it is
///   /blackout    — stop everything and take every channel to zero
///
/// This is unauthenticated by design: it's meant for the node's own isolated
/// Wi-Fi, which has no internet. Don't expose the tablet to a public network
/// with this switched on.
class RemoteControlServer {
  final ReadProvider read;

  RemoteControlServer(this.read);

  HttpServer? _server;
  String? lastError;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Binds on every interface so the tablet is reachable at its Wi-Fi
  /// address. Returns false and sets [lastError] if the port is taken.
  Future<bool> start(int port) async {
    await stop();
    lastError = null;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handle, onError: (Object e) => lastError = e.toString());
      return true;
    } catch (e) {
      lastError = e.toString();
      _server = null;
      return false;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    try {
      switch (path) {
        case '/trigger':
          final message = await fireByName(read, query['name'] ?? '');
          _writeJson(request, {'ok': true, 'message': message});
        case '/stop':
          stopPlayback(read);
          _writeJson(request, {'ok': true, 'message': 'Stopped'});
        case '/blackout':
          await blackoutEverything(read);
          _writeJson(request, {'ok': true, 'message': 'Blackout'});
        case '/endpoints':
          _writeText(request, _endpointsDocument());
        case '/':
        case '/status':
          _writeJson(request, _status());
        default:
          request.response.statusCode = HttpStatus.notFound;
          _writeJson(request, {'ok': false, 'message': 'Unknown endpoint "$path"'});
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      _writeJson(request, {'ok': false, 'message': e.toString()});
    }
  }

  /// The menu a Wear OS client (HttpClient-WearOS) pulls to populate itself:
  /// `<dashes> <id>,<name>[,<path>]`, one line per entry, nesting by dash
  /// count, served as text/plain. That app appends `/endpoints` to its base
  /// URL, which is why this lives here.
  ///
  /// Only what's pinned to the Dashboard is listed, so the watch mirrors the
  /// tiles you curated rather than every bank in the project — and it
  /// re-reads this, so adding a tile is enough to see it on your wrist.
  String _endpointsDocument() {
    // Commas separate the fields, so a name carrying one would split the
    // line; the trigger still fires on the real name in the URL.
    String display(String name) => name.replaceAll(',', ' ').trim();
    String path(String name) => '/trigger?name=${Uri.encodeComponent(name)}';

    final targets = remoteTargets(read).where((t) => t.onDashboard).toList();
    final playable = targets.where((t) => t.kind != 'smart').toList();
    final smart = targets.where((t) => t.kind == 'smart').toList();
    final lines = <String>[];
    var index = 0;

    if (playable.isNotEmpty) {
      lines.add('- trg,Triggers');
      for (final target in playable) {
        lines.add('-- t${index++},${display(target.name)},${path(target.name)}');
      }
    }
    if (smart.isNotEmpty) {
      lines.add('- smt,Smart');
      for (final target in smart) {
        lines.add('-- s${index++},${display(target.name)},${path(target.name)}');
      }
    }
    lines.add('- ctl,Control');
    lines.add('-- stop,Stop,/stop');
    lines.add('-- blk,Blackout,/blackout');
    return lines.join('\n');
  }

  Map<String, dynamic> _status() {
    final nowPlaying = read(nowPlayingProvider);
    return {
      'ok': true,
      'nowPlaying': nowPlaying == null
          ? null
          : {'name': nowPlaying.name, 'kind': nowPlaying.kind.name},
      'targets': [
        for (final target in remoteTargets(read)) {'name': target.name, 'kind': target.kind},
      ],
    };
  }

  void _writeText(HttpRequest request, String body) {
    request.response
      ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
      ..write(body)
      ..close();
  }

  void _writeJson(HttpRequest request, Map<String, dynamic> body) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }
}

/// The Wi-Fi address to point a macro at, or null if there's no usable one.
Future<String?> localWifiAddress() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
  } catch (_) {
    // No network yet — the Settings screen just shows nothing.
  }
  return null;
}

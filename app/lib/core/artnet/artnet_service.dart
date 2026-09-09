import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../models/artnet_settings.dart';
import '../../models/universe_config.dart';
import 'artnet_packet.dart';

class ArtPollResult {
  final bool success;
  final Duration latency;
  final String? replyFrom;

  const ArtPollResult({
    required this.success,
    required this.latency,
    this.replyFrom,
  });
}

/// Owns the UDP socket and per-universe DMX buffers, and talks Art-Net to
/// whatever node is configured in [ArtNetSettings] (e.g. an EasyNode Blue).
class ArtNetService {
  RawDatagramSocket? _socket;
  ArtNetSettings _settings = const ArtNetSettings();

  final Map<String, Uint8List> _buffers = {};
  final Map<String, int> _sequences = {};
  final Map<String, UniverseConfig> _knownUniverses = {};

  Timer? _keepAliveTimer;
  bool _demoMode = false;

  /// Demo mode counts as connected on purpose: every screen gates triggers
  /// on this, and the whole point is to let a show be written with no node
  /// on the network. Nothing is transmitted — [_send] has no socket to use —
  /// but the channel buffers still update, which is what the 2D stage view
  /// draws from.
  bool get isConnected => _socket != null || _demoMode;
  bool get isDemoMode => _demoMode;
  ArtNetSettings get settings => _settings;

  /// Opens the sending socket. Call once, e.g. from the Settings screen.
  Future<void> connect(ArtNetSettings settings) async {
    await disconnect();
    _settings = settings;
    _demoMode = settings.demoMode;
    if (_demoMode) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = settings.broadcast;
    _socket = socket;

    // Re-send the last known state of every universe periodically so a
    // dropped UDP packet (or a node that just powered on) doesn't leave
    // fixtures stuck on a stale value.
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshAll());
  }

  Future<void> disconnect() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _socket?.close();
    _socket = null;
    _demoMode = false;
  }

  void updateSettings(ArtNetSettings settings) {
    _settings = settings;
    _socket?.broadcastEnabled = settings.broadcast;
  }

  /// Sets one channel in [universe]'s buffer. Pass `send: false` when
  /// setting several channels in a row (e.g. a whole fixture or scene) and
  /// call [flush] once afterwards — sending one packet per changed channel
  /// floods the node with redundant traffic and can overwhelm it.
  void setChannel(UniverseConfig universe, int channel, int value, {bool send = true}) {
    final buffer = _bufferFor(universe);
    if (channel < 0 || channel > 511) return;
    buffer[channel] = value.clamp(0, 255);
    if (send) _send(universe);
  }

  void setUniverseData(UniverseConfig universe, Uint8List data, {bool send = true}) {
    final buffer = _bufferFor(universe);
    buffer.setRange(0, data.length.clamp(0, 512), data);
    if (send) _send(universe);
  }

  /// Sends the current buffer for [universe] as one Art-Net packet. Call
  /// this once after a batch of [setChannel](send: false) calls.
  void flush(UniverseConfig universe) => _send(universe);

  void blackoutUniverse(UniverseConfig universe) {
    _bufferFor(universe).fillRange(0, 512, 0);
    _send(universe);
  }

  void blackoutAll(Iterable<UniverseConfig> universes) {
    for (final universe in universes) {
      blackoutUniverse(universe);
    }
  }

  /// Sends an ArtPoll and waits briefly for any ArtPollReply, to verify a
  /// node is actually reachable at the configured host/port.
  Future<ArtPollResult> testConnection({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    probe.broadcastEnabled = true;
    final stopwatch = Stopwatch()..start();
    final completer = Completer<ArtPollResult>();

    final subscription = probe.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = probe.receive();
      if (datagram == null) return;
      if (isArtPollReply(datagram.data) && !completer.isCompleted) {
        stopwatch.stop();
        completer.complete(
          ArtPollResult(
            success: true,
            latency: stopwatch.elapsed,
            replyFrom: datagram.address.address,
          ),
        );
      }
    });

    try {
      probe.send(buildArtPollPacket(), InternetAddress(_settings.host), _settings.port);
      return await completer.future.timeout(
        timeout,
        onTimeout: () => ArtPollResult(success: false, latency: stopwatch.elapsed),
      );
    } catch (_) {
      return ArtPollResult(success: false, latency: stopwatch.elapsed);
    } finally {
      await subscription.cancel();
      probe.close();
    }
  }

  /// The last value sent (or buffered) for one channel — used to compute
  /// fade start points without keeping a second copy of the state.
  int getChannelValue(UniverseConfig universe, int channel) {
    if (channel < 0 || channel > 511) return 0;
    return _buffers[universe.id]?[channel] ?? 0;
  }

  Uint8List _bufferFor(UniverseConfig universe) {
    _knownUniverses[universe.id] = universe;
    return _buffers.putIfAbsent(universe.id, () => Uint8List(512));
  }

  void _refreshAll() {
    for (final universe in _knownUniverses.values) {
      _send(universe);
    }
  }

  void _send(UniverseConfig universe) {
    final socket = _socket;
    if (socket == null) return;
    final nextSequence = ((_sequences[universe.id] ?? 0) % 255) + 1;
    _sequences[universe.id] = nextSequence;
    final packet = buildArtDmxPacket(
      net: universe.net,
      subNet: universe.subNet,
      universe: universe.universe,
      sequence: nextSequence,
      dmxData: _buffers[universe.id]!,
    );
    socket.send(packet, InternetAddress(_settings.host), _settings.port);
  }
}

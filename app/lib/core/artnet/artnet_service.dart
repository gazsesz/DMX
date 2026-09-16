import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../models/artnet_settings.dart';
import '../../models/universe_config.dart';
import 'artnet_packet.dart';
import 'sacn_packet.dart';

/// A momentary effect layered over a universe's frame on its way out — see
/// `momentary_fx.dart`. Returning the frame it was handed means "unchanged".
typedef OutputOverride = Uint8List Function(UniverseConfig universe, Uint8List frame);

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
/// whatever node is configured in [ArtNetSettings] (e.g. an EasyNode Blue),
/// and/or sACN to each universe's multicast group — see [ArtNetSettings.protocol].
class ArtNetService {
  RawDatagramSocket? _socket;
  ArtNetSettings _settings = const ArtNetSettings();

  final Map<String, Uint8List> _buffers = {};
  final Map<String, int> _sequences = {};
  final Map<String, UniverseConfig> _knownUniverses = {};

  Timer? _keepAliveTimer;
  bool _demoMode = false;

  /// This sender's E1.31 component identifier. Receivers merge and
  /// prioritise by CID, so it has to be stable for as long as the app runs
  /// — one per service instance, generated once.
  final Uint8List _cid = _randomCid();

  /// What a console shows in its list of sACN sources.
  static const _sourceName = 'SmART DMX Controller';

  double _master = 1.0;
  Map<String, Set<int>> _masterChannels = const {};

  /// Grand master, 0..1 — scales intensity on the way out *only*.
  ///
  /// Deliberately applied at send time rather than to the buffers: the
  /// buffers keep the levels the show actually programmed, so pulling the
  /// master down and back up restores exactly what was there. Writing the
  /// scaled values into the buffers instead would quietly destroy the
  /// original levels the first time anyone touched it.
  double get master => _master;

  set master(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _master) return;
    _master = clamped;
    _refreshAll();
  }

  OutputOverride? _override;

  /// The momentary layer — strobe, blinder, freeze — applied to every frame
  /// on its way out.
  ///
  /// Held *outside* the buffers for the same reason [master] is: the buffers
  /// keep the levels the show programmed, so letting go of a momentary button
  /// puts the previous look straight back instead of having to rebuild it.
  /// It sits under the master, so pulling the master down still takes a
  /// blinded or frozen stage with it.
  ///
  /// Setting it re-sends every universe: an effect has to reach the rig the
  /// moment the finger lands, not on the next keep-alive.
  OutputOverride? get outputOverride => _override;

  set outputOverride(OutputOverride? override) {
    _override = override;
    _refreshAll();
  }

  /// Re-sends every known universe. What a momentary effect calls when its
  /// own layer changed — a strobe's phase flipping — and the show itself
  /// has written nothing to flush.
  void refreshOutput() => _refreshAll();

  /// A copy of [universe]'s current buffer, for an effect that has to hold on
  /// to the look it started from.
  Uint8List snapshotFrame(UniverseConfig universe) => Uint8List.fromList(_bufferFor(universe));

  /// Which channels [master] scales, per universe — see `masterChannelsFor`.
  /// Everything not listed goes out untouched, so pan/tilt, gobo and strobe
  /// are never dimmed.
  void setMasterChannels(Map<String, Set<int>> byUniverse) {
    _masterChannels = byUniverse;
    if (_master < 1.0) _refreshAll();
  }

  /// The buffer as it should leave the device. Returns the buffer itself at
  /// full master, so the normal case allocates nothing.
  Uint8List _withMaster(UniverseConfig universe, Uint8List buffer) {
    if (_master >= 1.0) return buffer;
    final channels = _masterChannels[universe.id];
    if (channels == null || channels.isEmpty) return buffer;
    final scaled = Uint8List.fromList(buffer);
    for (final channel in channels) {
      if (channel < 0 || channel > 511) continue;
      scaled[channel] = (buffer[channel] * _master).round().clamp(0, 255);
    }
    return scaled;
  }

  static Uint8List _randomCid() {
    final random = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < 16; i++) random.nextInt(256)]);
  }

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

  /// Sends the current buffer for [universe] on every enabled protocol. Call
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
    final buffer = _buffers[universe.id]!;
    final data = _withMaster(universe, _override?.call(universe, buffer) ?? buffer);
    final protocol = _settings.protocol;

    if (protocol.sendsArtNet) {
      socket.send(
        buildArtDmxPacket(
          net: universe.net,
          subNet: universe.subNet,
          universe: universe.universe,
          sequence: nextSequence,
          dmxData: data,
        ),
        InternetAddress(_settings.host),
        _settings.port,
      );
    }

    if (protocol.sendsSacn) {
      // sACN addresses the universe, not the node: the packet goes to the
      // universe's own multicast group and whichever nodes subscribed to it
      // pick it up. Nothing here depends on the configured host.
      socket.send(
        buildSacnDataPacket(
          universe: universe.sacnUniverse,
          sequence: nextSequence,
          dmxData: data,
          cid: _cid,
          sourceName: _sourceName,
          priority: _settings.sacnPriority,
        ),
        InternetAddress(sacnMulticastAddress(universe.sacnUniverse)),
        sacnPort,
      );
    }
  }
}

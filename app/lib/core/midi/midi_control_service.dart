import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'midi_connections.dart';
import 'midi_input_message.dart';

/// A controller the user picked, remembered by id and name: a USB device's
/// id can change between plug-ins, so a reconnect also tries the name.
class RememberedMidiDevice {
  final String id;
  final String name;
  final bool bluetooth;

  const RememberedMidiDevice({required this.id, required this.name, this.bluetooth = false});

  bool matches(MidiDevice device) => device.id == id || device.name == name;

  String encode() => '${bluetooth ? 'ble' : 'usb'}\u0001$id\u0001$name';

  static RememberedMidiDevice? decode(String raw) {
    final parts = raw.split('\u0001');
    if (parts.length != 3) return null;
    return RememberedMidiDevice(id: parts[1], name: parts[2], bluetooth: parts[0] == 'ble');
  }
}

/// Listens to MIDI controllers (USB and Bluetooth) for the MIDI learn
/// feature: keeps the chosen devices connected, decodes what they send, and
/// either hands the next message to a waiting [learn] or passes every
/// message to [onMessage] for the mappings to act on.
///
/// Several controllers can be connected at once; the mappings don't care
/// which one a message came from, so swapping one APC mini for another
/// keeps the layout.
class MidiControlService {
  static const _owner = 'controllers';

  final MidiCommand _midi;

  /// Called for every decoded message while not learning.
  void Function(MidiInputMessage message)? onMessage;

  /// Called whenever the remembered list changes, for the caller to persist.
  void Function(List<RememberedMidiDevice> devices)? onRememberedChanged;

  MidiControlService({MidiCommand? midi}) : _midi = midi ?? MidiCommand();

  final Map<String, MidiDevice> _connected = {};
  final Map<String, MidiRunningStatus> _running = {};
  List<RememberedMidiDevice> _remembered = const [];
  StreamSubscription<MidiPacket>? _packets;
  StreamSubscription<MidiSetupChange>? _setup;
  Completer<MidiInputMessage?>? _learning;
  bool _bleStarted = false;
  bool _scanning = false;
  Timer? _scanStop;

  /// The last message from any controller, for the live monitor.
  final ValueNotifier<MidiInputMessage?> lastMessage = ValueNotifier(null);

  /// Bumps whenever the connected set or the remembered list changes.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String? lastError;

  bool get isLearning => _learning != null && !_learning!.isCompleted;
  bool get isScanning => _scanning;
  List<RememberedMidiDevice> get remembered => _remembered;
  bool isConnected(MidiDevice device) => _connected.containsKey(device.id);
  List<MidiDevice> get connectedDevices => _connected.values.toList();

  /// Whether this build can talk Bluetooth MIDI at all.
  bool get bluetoothAvailable => _midi.isTransportEnabled(MidiTransport.ble) && _bleConfigured;
  static bool _bleConfigured = false;

  /// Called once from `main()` after the BLE transport is attached.
  static void markBluetoothConfigured() => _bleConfigured = true;

  /// Starts listening and reconnects whatever was remembered — called at
  /// startup with the saved list.
  Future<void> start(List<RememberedMidiDevice> remembered) async {
    _remembered = remembered;
    _packets ??= _midi.onMidiPacketReceived?.listen(_onPacket);
    _setup ??= _midi.onMidiSetupChanged?.listen((_) => reconnectRemembered());
    if (_remembered.isEmpty) return;
    await reconnectRemembered();
    // A Bluetooth controller is only seen after a scan.
    if (_remembered.any((d) => d.bluetooth) && bluetoothAvailable) {
      unawaited(scanBluetooth(quiet: true));
    }
  }

  /// Every MIDI device visible right now (USB, and Bluetooth ones a scan found).
  Future<List<MidiDevice>> devices() async {
    try {
      // A platform that never answers (no MIDI service) mustn't leave the
      // list spinning forever.
      return await (_midi.devices).timeout(const Duration(seconds: 5), onTimeout: () => const []) ?? const [];
    } catch (e) {
      lastError = 'Could not list MIDI devices: $e';
      return const [];
    }
  }

  /// Connects whichever remembered controllers are visible and not yet
  /// connected — after a startup, a scan, or a cable going back in.
  Future<void> reconnectRemembered() async {
    final visible = await devices();
    // An unplugged controller drops off the list: forget the dead
    // connection so plugging it back in reconnects it.
    final visibleIds = {for (final d in visible) d.id};
    for (final id in [..._connected.keys]) {
      if (visibleIds.contains(id)) continue;
      final gone = _connected.remove(id)!;
      _running.remove(id);
      MidiConnections.release(_midi, gone, _owner);
      revision.value++;
    }
    if (_remembered.isEmpty) return;
    for (final device in visible) {
      if (_connected.containsKey(device.id)) continue;
      if (_remembered.any((r) => r.matches(device))) await _open(device);
    }
  }

  /// Connects [device] as a controller and remembers it for next time.
  Future<bool> connect(MidiDevice device) async {
    final ok = await _open(device);
    if (ok) {
      _remember(device);
    }
    return ok;
  }

  /// Disconnects [device] and forgets it.
  void disconnect(MidiDevice device) {
    final open = _connected.remove(device.id);
    if (open != null) MidiConnections.release(_midi, open, _owner);
    _running.remove(device.id);
    _remembered = [for (final r in _remembered) if (!r.matches(device)) r];
    onRememberedChanged?.call(_remembered);
    revision.value++;
  }

  Future<bool> _open(MidiDevice device) async {
    lastError = null;
    _packets ??= _midi.onMidiPacketReceived?.listen(_onPacket);
    try {
      await MidiConnections.acquire(_midi, device, _owner);
    } catch (e) {
      lastError = 'Could not connect to ${device.name}: $e';
      revision.value++;
      return false;
    }
    _connected[device.id] = device;
    _running[device.id] = MidiRunningStatus();
    revision.value++;
    return true;
  }

  void _remember(MidiDevice device) {
    final entry = RememberedMidiDevice(
      id: device.id,
      name: device.name,
      bluetooth: device.type == MidiDeviceType.ble,
    );
    _remembered = [for (final r in _remembered) if (!r.matches(device)) r, entry];
    onRememberedChanged?.call(_remembered);
    revision.value++;
  }

  /// Turns Bluetooth on (asking for permission the first time) and looks
  /// for BLE MIDI controllers for [duration]. Found ones show up in
  /// [devices]; remembered ones are reconnected as they appear.
  Future<String?> scanBluetooth({Duration duration = const Duration(seconds: 12), bool quiet = false}) async {
    if (!bluetoothAvailable) return 'Bluetooth MIDI is not available on this device';
    try {
      if (!_bleStarted) {
        await _midi.startBluetooth();
        await _midi.waitUntilBluetoothIsInitialized().timeout(const Duration(seconds: 5), onTimeout: () {});
        _bleStarted = true;
      }
      if (_midi.bluetoothState != BluetoothState.poweredOn) {
        return _midi.bluetoothState == BluetoothState.unauthorized
            ? 'Bluetooth permission was denied — allow "Nearby devices" for the app in Android settings'
            : 'Bluetooth is off — turn it on and scan again';
      }
      await _midi.startScanningForBluetoothDevices();
      _scanning = true;
      revision.value++;
      _scanStop?.cancel();
      _scanStop = Timer(duration, stopScan);
      // Pick remembered controllers up as soon as the scan sees them.
      for (var i = 0; i < duration.inSeconds ~/ 2 && _scanning; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await reconnectRemembered();
        revision.value++;
      }
      return null;
    } catch (e) {
      _scanning = false;
      revision.value++;
      return quiet ? null : 'Bluetooth scan failed: $e';
    }
  }

  void stopScan() {
    _scanStop?.cancel();
    if (!_scanning) return;
    _scanning = false;
    try {
      _midi.stopScanningForBluetoothDevices();
    } catch (_) {}
    revision.value++;
  }

  /// Waits for the next press, fader move or program change on any
  /// connected controller and returns it (null if [cancelLearn] is called).
  /// While waiting, mappings don't fire — touching a pad to learn it
  /// shouldn't also start the bank it's currently bound to.
  Future<MidiInputMessage?> learn() {
    _learning?.complete(null);
    final completer = Completer<MidiInputMessage?>();
    _learning = completer;
    return completer.future;
  }

  void cancelLearn() {
    final pending = _learning;
    _learning = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  void _onPacket(MidiPacket packet) {
    final deviceId = packet.device.id;
    if (!_connected.containsKey(deviceId)) return;
    final messages = parseMidiPacket(packet.data, _running.putIfAbsent(deviceId, MidiRunningStatus.new));
    for (final message in messages) {
      handleMessage(message);
    }
  }

  /// One decoded message — public so tests can feed the service directly.
  @visibleForTesting
  void handleMessage(MidiInputMessage message) {
    lastMessage.value = message;
    final learning = _learning;
    if (learning != null && !learning.isCompleted) {
      // A release says nothing new: learn on the press.
      if (message.noteOff) return;
      _learning = null;
      learning.complete(message);
      return;
    }
    onMessage?.call(message);
  }

  void dispose() {
    cancelLearn();
    stopScan();
    _packets?.cancel();
    _setup?.cancel();
    for (final device in _connected.values) {
      MidiConnections.release(_midi, device, _owner);
    }
    _connected.clear();
    lastMessage.dispose();
    revision.dispose();
  }
}

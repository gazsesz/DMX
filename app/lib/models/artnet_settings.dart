import 'output_protocol.dart';

/// Connection settings for reaching the EasyNode Blue (or any Art-Net or
/// sACN node).
class ArtNetSettings {
  final String deviceName;
  final String host;
  final int port;
  final bool broadcast;

  /// Which protocol(s) leave the device. Art-Net is unicast/broadcast to
  /// [host]; sACN goes to its own multicast group per universe and ignores
  /// [host] entirely, which is why there's nothing else to configure for it
  /// beyond the priority.
  final OutputProtocol protocol;

  /// E1.31 source priority, 0-200 (100 is the standard default). Only used
  /// when sACN is being sent: a receiver takes the highest-priority source
  /// it can see, so raising this lets the tablet override a console.
  final int sacnPriority;

  /// Work without a node: everything behaves as connected, but no packets
  /// leave the device — the 2D stage view reads the same channel buffers, so
  /// scenes and chases can be written and watched offline.
  final bool demoMode;

  const ArtNetSettings({
    this.deviceName = 'EasyNode Blue',
    this.host = '192.168.1.50',
    this.port = 6454,
    this.broadcast = false,
    this.protocol = OutputProtocol.artNet,
    this.sacnPriority = 100,
    this.demoMode = false,
  });

  ArtNetSettings copyWith({
    String? deviceName,
    String? host,
    int? port,
    bool? broadcast,
    OutputProtocol? protocol,
    int? sacnPriority,
    bool? demoMode,
  }) {
    return ArtNetSettings(
      deviceName: deviceName ?? this.deviceName,
      host: host ?? this.host,
      port: port ?? this.port,
      broadcast: broadcast ?? this.broadcast,
      protocol: protocol ?? this.protocol,
      sacnPriority: sacnPriority ?? this.sacnPriority,
      demoMode: demoMode ?? this.demoMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'host': host,
    'port': port,
    'broadcast': broadcast,
    'protocol': protocol.name,
    'sacnPriority': sacnPriority,
    'demoMode': demoMode,
  };

  factory ArtNetSettings.fromJson(Map<String, dynamic> json) {
    return ArtNetSettings(
      deviceName: json['deviceName'] as String? ?? 'EasyNode Blue',
      host: json['host'] as String? ?? '192.168.1.50',
      port: json['port'] as int? ?? 6454,
      broadcast: json['broadcast'] as bool? ?? false,
      protocol: OutputProtocol.fromName(json['protocol'] as String?),
      sacnPriority: (json['sacnPriority'] as int? ?? 100).clamp(0, 200),
      demoMode: json['demoMode'] as bool? ?? false,
    );
  }
}

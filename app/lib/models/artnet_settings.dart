/// Connection settings for reaching the EasyNode Blue (or any Art-Net node).
class ArtNetSettings {
  final String deviceName;
  final String host;
  final int port;
  final bool broadcast;

  /// Work without a node: everything behaves as connected, but no packets
  /// leave the device — the 2D stage view reads the same channel buffers, so
  /// scenes and chases can be written and watched offline.
  final bool demoMode;

  const ArtNetSettings({
    this.deviceName = 'EasyNode Blue',
    this.host = '192.168.1.50',
    this.port = 6454,
    this.broadcast = false,
    this.demoMode = false,
  });

  ArtNetSettings copyWith({
    String? deviceName,
    String? host,
    int? port,
    bool? broadcast,
    bool? demoMode,
  }) {
    return ArtNetSettings(
      deviceName: deviceName ?? this.deviceName,
      host: host ?? this.host,
      port: port ?? this.port,
      broadcast: broadcast ?? this.broadcast,
      demoMode: demoMode ?? this.demoMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'host': host,
    'port': port,
    'broadcast': broadcast,
    'demoMode': demoMode,
  };

  factory ArtNetSettings.fromJson(Map<String, dynamic> json) {
    return ArtNetSettings(
      deviceName: json['deviceName'] as String? ?? 'EasyNode Blue',
      host: json['host'] as String? ?? '192.168.1.50',
      port: json['port'] as int? ?? 6454,
      broadcast: json['broadcast'] as bool? ?? false,
      demoMode: json['demoMode'] as bool? ?? false,
    );
  }
}

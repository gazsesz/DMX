/// Connection settings for reaching the EasyNode Blue (or any Art-Net node).
class ArtNetSettings {
  final String deviceName;
  final String host;
  final int port;
  final bool broadcast;

  const ArtNetSettings({
    this.deviceName = 'EasyNode Blue',
    this.host = '192.168.1.50',
    this.port = 6454,
    this.broadcast = false,
  });

  ArtNetSettings copyWith({
    String? deviceName,
    String? host,
    int? port,
    bool? broadcast,
  }) {
    return ArtNetSettings(
      deviceName: deviceName ?? this.deviceName,
      host: host ?? this.host,
      port: port ?? this.port,
      broadcast: broadcast ?? this.broadcast,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'host': host,
    'port': port,
    'broadcast': broadcast,
  };

  factory ArtNetSettings.fromJson(Map<String, dynamic> json) {
    return ArtNetSettings(
      deviceName: json['deviceName'] as String? ?? 'EasyNode Blue',
      host: json['host'] as String? ?? '192.168.1.50',
      port: json['port'] as int? ?? 6454,
      broadcast: json['broadcast'] as bool? ?? false,
    );
  }
}

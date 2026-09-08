/// One Art-Net Net/Sub-Net/Universe address the app can output DMX on.
class UniverseConfig {
  final String id;
  final String name;
  final int net;
  final int subNet;
  final int universe;

  const UniverseConfig({
    required this.id,
    required this.name,
    this.net = 0,
    this.subNet = 0,
    required this.universe,
  });

  UniverseConfig copyWith({
    String? name,
    int? net,
    int? subNet,
    int? universe,
  }) {
    return UniverseConfig(
      id: id,
      name: name ?? this.name,
      net: net ?? this.net,
      subNet: subNet ?? this.subNet,
      universe: universe ?? this.universe,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'net': net,
    'subNet': subNet,
    'universe': universe,
  };

  factory UniverseConfig.fromJson(Map<String, dynamic> json) {
    return UniverseConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      net: json['net'] as int? ?? 0,
      subNet: json['subNet'] as int? ?? 0,
      universe: json['universe'] as int,
    );
  }
}

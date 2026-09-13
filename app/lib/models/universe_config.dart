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

  /// The 15-bit Art-Net Port-Address this universe resolves to.
  int get portAddress => ((net & 0x7F) << 8) | ((subNet & 0x0F) << 4) | (universe & 0x0F);

  /// The E1.31 universe number to send on. Art-Net counts port addresses
  /// from 0 and sACN counts universes from 1, so the default rig (Net 0,
  /// Sub 0, Universe 0) lands on sACN universe 1 — which is what every
  /// console and node expects "the first universe" to be.
  int get sacnUniverse => portAddress + 1;

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

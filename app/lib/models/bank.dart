/// A grid of scene slots that can be triggered from the Dashboard.
class Bank {
  final String id;
  final String name;
  final List<String?> sceneSlots;

  /// True for a bank built by the "Beat Flash" preset — a two-slot dark/lit
  /// pair meant to be run with Beat Sync at the Flash rate. Drives behaviour
  /// that only makes sense for that shape: a Smart Program suspends
  /// auto-fade while one of these is the active zone, and the player looks
  /// here for [flashFadeOutMs] instead of the usual per-step fade.
  final bool isBeatFlash;

  /// How long the *lit → dark* transition takes when this bank plays at the
  /// Flash beat rate, in milliseconds. Zero (the default) is a hard cut —
  /// the classic stab. The *dark → lit* attack is never affected: a flash
  /// that fades in on the way up isn't a flash.
  final int flashFadeOutMs;

  const Bank({
    required this.id,
    required this.name,
    required this.sceneSlots,
    this.isBeatFlash = false,
    this.flashFadeOutMs = 0,
  });

  Bank copyWith({
    String? name,
    List<String?>? sceneSlots,
    bool? isBeatFlash,
    int? flashFadeOutMs,
  }) {
    return Bank(
      id: id,
      name: name ?? this.name,
      sceneSlots: sceneSlots ?? this.sceneSlots,
      isBeatFlash: isBeatFlash ?? this.isBeatFlash,
      flashFadeOutMs: flashFadeOutMs ?? this.flashFadeOutMs,
    );
  }

  Bank resized(int newSize) {
    final slots = List<String?>.filled(newSize, null);
    for (var i = 0; i < sceneSlots.length && i < newSize; i++) {
      slots[i] = sceneSlots[i];
    }
    return copyWith(sceneSlots: slots);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sceneSlots': sceneSlots,
    'isBeatFlash': isBeatFlash,
    'flashFadeOutMs': flashFadeOutMs,
  };

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'] as String,
      name: json['name'] as String,
      sceneSlots: (json['sceneSlots'] as List).map((e) => e as String?).toList(),
      isBeatFlash: json['isBeatFlash'] as bool? ?? false,
      flashFadeOutMs: json['flashFadeOutMs'] as int? ?? 0,
    );
  }
}

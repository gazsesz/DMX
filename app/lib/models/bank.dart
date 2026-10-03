/// One bank step's own Hold/Fade, set on that slot — wins over the bank's
/// own timing and the dock's, wherever the bank plays.
class SlotTiming {
  final int holdMs;
  final int fadeMs;

  const SlotTiming({required this.holdMs, required this.fadeMs});

  Duration get hold => Duration(milliseconds: holdMs);
  Duration get fade => Duration(milliseconds: fadeMs);

  SlotTiming copyWith({int? holdMs, int? fadeMs}) =>
      SlotTiming(holdMs: holdMs ?? this.holdMs, fadeMs: fadeMs ?? this.fadeMs);

  Map<String, dynamic> toJson() => {'holdMs': holdMs, 'fadeMs': fadeMs};

  static SlotTiming? fromJson(dynamic json) {
    if (json is! Map) return null;
    return SlotTiming(
      holdMs: ((json['holdMs'] as num?)?.toInt() ?? 1200).clamp(20, 60000),
      fadeMs: ((json['fadeMs'] as num?)?.toInt() ?? 300).clamp(0, 120000),
    );
  }

  @override
  bool operator ==(Object other) => other is SlotTiming && other.holdMs == holdMs && other.fadeMs == fadeMs;

  @override
  int get hashCode => Object.hash(holdMs, fadeMs);
}

/// A grid of scene slots that can be triggered from the Dashboard.
class Bank {
  final String id;
  final String name;
  final List<String?> sceneSlots;

  /// True for a bank built by the "Beat Flash" preset — a two-slot dark/lit
  /// pair meant to be run with Beat Sync at the Flash rate. Drives behaviour
  /// that only makes sense for that shape: it always steps at the Flash rate
  /// while beat synced, a Smart Program suspends auto-fade while one of
  /// these is the active zone, and the player looks here for
  /// [flashFadeOutMs] instead of the usual per-step fade.
  final bool isBeatFlash;

  /// How long the *lit → dark* transition takes when this bank plays at the
  /// Flash beat rate, in milliseconds. Zero (the default) is a hard cut —
  /// the classic stab. The *dark → lit* attack is never affected: a flash
  /// that fades in on the way up isn't a flash.
  final int flashFadeOutMs;

  /// Plays at its own [holdMs]/[fadeMs] instead of the app-wide Hold/Fade
  /// in the control dock — and, fading at its own pace, auto-fade leaves it
  /// alone too. Off by default: most banks are meant to follow the show's
  /// tempo.
  final bool ownTiming;
  final int holdMs;
  final int fadeMs;

  /// Per-step Hold/Fade, by slot index (same order as [sceneSlots]; may be
  /// shorter). Null for a step that follows the bank — see [timingAt].
  final List<SlotTiming?> slotTimings;

  const Bank({
    required this.id,
    required this.name,
    required this.sceneSlots,
    this.isBeatFlash = false,
    this.flashFadeOutMs = 0,
    this.ownTiming = false,
    this.holdMs = 1200,
    this.fadeMs = 300,
    this.slotTimings = const [],
  });

  Duration get hold => Duration(milliseconds: holdMs);
  Duration get fade => Duration(milliseconds: fadeMs);

  /// The step at [slot]'s own timing, or null when it follows the bank.
  SlotTiming? timingAt(int slot) => slot >= 0 && slot < slotTimings.length ? slotTimings[slot] : null;

  bool get hasStepTimings => slotTimings.any((t) => t != null);

  Bank copyWith({
    String? name,
    List<String?>? sceneSlots,
    bool? isBeatFlash,
    int? flashFadeOutMs,
    bool? ownTiming,
    int? holdMs,
    int? fadeMs,
    List<SlotTiming?>? slotTimings,
  }) {
    return Bank(
      id: id,
      name: name ?? this.name,
      sceneSlots: sceneSlots ?? this.sceneSlots,
      isBeatFlash: isBeatFlash ?? this.isBeatFlash,
      flashFadeOutMs: flashFadeOutMs ?? this.flashFadeOutMs,
      ownTiming: ownTiming ?? this.ownTiming,
      holdMs: holdMs ?? this.holdMs,
      fadeMs: fadeMs ?? this.fadeMs,
      slotTimings: slotTimings ?? this.slotTimings,
    );
  }

  Bank resized(int newSize) {
    final slots = List<String?>.filled(newSize, null);
    for (var i = 0; i < sceneSlots.length && i < newSize; i++) {
      slots[i] = sceneSlots[i];
    }
    return copyWith(
      sceneSlots: slots,
      slotTimings: [for (var i = 0; i < newSize && i < slotTimings.length; i++) slotTimings[i]],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sceneSlots': sceneSlots,
    'isBeatFlash': isBeatFlash,
    'flashFadeOutMs': flashFadeOutMs,
    'ownTiming': ownTiming,
    'holdMs': holdMs,
    'fadeMs': fadeMs,
    if (hasStepTimings) 'slotTimings': [for (final t in slotTimings) t?.toJson()],
  };

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'] as String,
      name: json['name'] as String,
      sceneSlots: (json['sceneSlots'] as List).map((e) => e as String?).toList(),
      isBeatFlash: json['isBeatFlash'] as bool? ?? false,
      flashFadeOutMs: json['flashFadeOutMs'] as int? ?? 0,
      ownTiming: json['ownTiming'] as bool? ?? false,
      holdMs: json['holdMs'] as int? ?? 1200,
      fadeMs: json['fadeMs'] as int? ?? 300,
      slotTimings: [for (final t in json['slotTimings'] as List? ?? const []) SlotTiming.fromJson(t)],
    );
  }
}

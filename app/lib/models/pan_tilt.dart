/// A moving head's position as two 16-bit values (0-65535): the coarse
/// channel is the high byte, the fine channel the low byte.
///
/// Positions are kept at 16 bits everywhere in the editor, even for a head
/// with no fine channels: the extra precision is just dropped on output, and
/// the same position then drives a 16-bit head in the same group smoothly.
class PanTilt {
  final int pan;
  final int tilt;

  const PanTilt(this.pan, this.tilt);

  static const max = 65535;

  /// Both axes at the middle of their travel — straight down (or up) along
  /// the yoke, pan at its centre.
  static const center = PanTilt(32768, 32768);

  /// Builds one from channel values, treating a missing fine channel as 0.
  factory PanTilt.fromChannels({required int pan, int panFine = 0, required int tilt, int tiltFine = 0}) {
    return PanTilt((pan.clamp(0, 255) << 8) | panFine.clamp(0, 255), (tilt.clamp(0, 255) << 8) | tiltFine.clamp(0, 255));
  }

  int get panCoarse => pan >> 8;
  int get panFine => pan & 0xFF;
  int get tiltCoarse => tilt >> 8;
  int get tiltFine => tilt & 0xFF;

  PanTilt clamped() => PanTilt(pan.clamp(0, max), tilt.clamp(0, max));

  PanTilt operator +(PanTilt other) => PanTilt(pan + other.pan, tilt + other.tilt);
  PanTilt operator -(PanTilt other) => PanTilt(pan - other.pan, tilt - other.tilt);

  List<int> toJson() => [pan, tilt];

  static PanTilt? fromJson(dynamic json) {
    if (json is! List || json.length < 2) return null;
    return PanTilt((json[0] as num).toInt(), (json[1] as num).toInt()).clamped();
  }

  @override
  bool operator ==(Object other) => other is PanTilt && other.pan == pan && other.tilt == tilt;

  @override
  int get hashCode => Object.hash(pan, tilt);

  @override
  String toString() => 'PanTilt($pan, $tilt)';
}

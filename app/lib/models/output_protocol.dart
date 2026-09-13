/// Which wire protocol the app sends DMX on.
///
/// Art-Net and sACN are the two protocols essentially every network node,
/// console and lighting program understands, and plenty of gear (the
/// EasyNode included) speaks both. They're not exclusive on the wire, so
/// [both] is a legitimate choice when part of a rig listens on each.
enum OutputProtocol {
  artNet,
  sacn,
  both;

  bool get sendsArtNet => this == artNet || this == both;
  bool get sendsSacn => this == sacn || this == both;

  String get label => switch (this) {
    OutputProtocol.artNet => 'Art-Net',
    OutputProtocol.sacn => 'sACN',
    OutputProtocol.both => 'Both',
  };

  static OutputProtocol fromName(String? name) =>
      OutputProtocol.values.firstWhere((p) => p.name == name, orElse: () => OutputProtocol.artNet);
}

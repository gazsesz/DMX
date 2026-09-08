/// A grid of scene slots that can be triggered from the Dashboard.
class Bank {
  final String id;
  final String name;
  final List<String?> sceneSlots;

  const Bank({required this.id, required this.name, required this.sceneSlots});

  Bank copyWith({String? name, List<String?>? sceneSlots}) {
    return Bank(id: id, name: name ?? this.name, sceneSlots: sceneSlots ?? this.sceneSlots);
  }

  Bank resized(int newSize) {
    final slots = List<String?>.filled(newSize, null);
    for (var i = 0; i < sceneSlots.length && i < newSize; i++) {
      slots[i] = sceneSlots[i];
    }
    return copyWith(sceneSlots: slots);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'sceneSlots': sceneSlots};

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'] as String,
      name: json['name'] as String,
      sceneSlots: (json['sceneSlots'] as List).map((e) => e as String?).toList(),
    );
  }
}

/// One independent playback slot — a named container that a bank/chase can
/// run on without superseding whatever another layer is running. Priority
/// and mergeHint are informational only: they describe how the two layers
/// are *expected* to be authored to avoid channel conflicts (see the Scene
/// editor's "INCLUDES" toggles), not a runtime conflict-resolution rule.
class Layer {
  final String id;
  final String name;
  final int priority;
  final String mergeHint;

  const Layer({required this.id, required this.name, required this.priority, this.mergeHint = ''});

  Layer copyWith({String? name, int? priority, String? mergeHint}) {
    return Layer(
      id: id,
      name: name ?? this.name,
      priority: priority ?? this.priority,
      mergeHint: mergeHint ?? this.mergeHint,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'priority': priority, 'mergeHint': mergeHint};

  factory Layer.fromJson(Map<String, dynamic> json) {
    return Layer(
      id: json['id'] as String,
      name: json['name'] as String,
      priority: json['priority'] as int? ?? 1,
      mergeHint: json['mergeHint'] as String? ?? '',
    );
  }
}

/// The permanent, non-deletable first layer — every screen/provider that
/// predates multi-layer support (Dashboard, Chases, Smart Programs, remote
/// control) implicitly targets this one.
const layer1Id = 'layer-1';

/// The id of the layer seeded by default alongside [layer1Id], matching the
/// always-available "Layer 2" toggle this screen replaces.
const layer2Id = 'layer-2';

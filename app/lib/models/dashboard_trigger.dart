enum TriggerKind { bank, chase }

/// A reference to a bank or chase the user chose to show as a Quick Trigger
/// on the Dashboard (rather than dumping every bank/chase there).
class DashboardTriggerRef {
  final String id;
  final TriggerKind kind;

  const DashboardTriggerRef({required this.id, required this.kind});

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name};

  factory DashboardTriggerRef.fromJson(Map<String, dynamic> json) {
    return DashboardTriggerRef(
      id: json['id'] as String,
      kind: TriggerKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => TriggerKind.bank,
      ),
    );
  }
}

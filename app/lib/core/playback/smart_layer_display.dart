import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/layer.dart';
import '../../models/smart_program.dart';

/// What a Smart Program plays (or would play) on one layer, for the screens
/// that list it layer by layer.
class SmartLayerLine {
  final Layer layer;
  final int layerIndex;

  /// The chase/bank name, or null when the layer has nothing in this zone.
  final String? targetName;

  /// The zone [targetName] comes from — Base when the layer has nothing of
  /// its own for the current zone and falls back.
  final SmartProgramZone? sourceZone;

  /// Set on an idle program's line for a layer with no Base: the zones it
  /// does join in, e.g. "Faster".
  final String? onlyIn;

  const SmartLayerLine({
    required this.layer,
    required this.layerIndex,
    this.targetName,
    this.sourceZone,
    this.onlyIn,
  });
}

String zoneLabel(SmartProgramZone zone) => switch (zone) {
  SmartProgramZone.base => 'Base',
  SmartProgramZone.faster => 'Faster',
  SmartProgramZone.slower => 'Slower',
};

String targetName(
  ProgramTarget target, {
  required List<Chase> chases,
  required List<Bank> banks,
  List<Layer> layers = const [],
}) {
  if (target.isBank) {
    final matches = banks.where((b) => b.id == target.id);
    return matches.isEmpty ? 'Missing bank' : matches.first.name;
  }
  final matches = chases.where((c) => c.id == target.id);
  if (matches.isEmpty) return 'Missing chase';
  final lane = target.lane;
  if (lane == null) return matches.first.name;
  final index = layers.indexWhere((l) => l.id == lane);
  return '${matches.first.name} (${index < 0 ? 'one layer' : 'L${index + 1}'})';
}

/// One line per existing layer [program] has anything on. With [zone] set
/// (the program is running) each line is what that layer plays right now;
/// without it, what each layer starts on.
List<SmartLayerLine> smartLayerLines(
  SmartProgram program, {
  required SmartProgramZone? zone,
  required List<Layer> layers,
  required List<Chase> chases,
  required List<Bank> banks,
}) {
  final lines = <SmartLayerLine>[];
  for (var i = 0; i < layers.length; i++) {
    final targets = program.targetsFor(layers[i].id);
    if (targets.isEmpty) continue;
    final shownZone = zone ?? SmartProgramZone.base;
    final target = targets.effective(shownZone);
    if (target == null) {
      final joins = [
        if (targets.faster != null) zoneLabel(SmartProgramZone.faster),
        if (targets.slower != null) zoneLabel(SmartProgramZone.slower),
      ];
      lines.add(SmartLayerLine(layer: layers[i], layerIndex: i, onlyIn: joins.join(' / ')));
      continue;
    }
    lines.add(SmartLayerLine(
      layer: layers[i],
      layerIndex: i,
      targetName: targetName(target, chases: chases, banks: banks, layers: layers),
      sourceZone: targets.explicit(shownZone) != null ? shownZone : SmartProgramZone.base,
    ));
  }
  return lines;
}

/// The one-line form of [smartLayerLines], e.g. "L1 RGB Wave · L2 Robot Sweep".
String smartLayerSummary(List<SmartLayerLine> lines) => lines
    .map((l) => 'L${l.layerIndex + 1} ${l.targetName ?? '—'}')
    .join(' · ');

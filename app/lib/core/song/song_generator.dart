import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../models/bank.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';
import 'song_analysis.dart';

/// How lively the generated show is: how often the look changes and which
/// kinds of section get moving-head movement.
enum SongStyle {
  club('Club', 'Frequent changes, movement on builds and drops', {SongSectionKind.build, SongSectionKind.drop}, 8),
  rock('Rock', 'Longer looks, movement on drops only', {SongSectionKind.drop}, 16),
  chill('Chill', 'Slow changes, little movement', {}, 32),
  show('Show', 'Busy: changes often, movement almost everywhere', {
    SongSectionKind.intro,
    SongSectionKind.build,
    SongSectionKind.drop,
    SongSectionKind.breakdown,
  }, 4);

  const SongStyle(this.label, this.description, this.movementKinds, this.baseBars);
  final String label;
  final String description;

  /// Section kinds that get a movement cue.
  final Set<SongSectionKind> movementKinds;

  /// Bars between look changes inside a long drop, before audacity scales it.
  final int baseBars;
}

class SongGeneratorOptions {
  final SongStyle style;

  /// 1 (calm) .. 5 (restless): scales how often the look changes.
  final int audacity;
  final int seed;
  final String lookLayerId;

  /// Layer the movement banks go on; null means no movement cues.
  final String? moveLayerId;

  /// Banks to draw looks from, per kind of section.
  final Map<SongSectionKind, List<String>> lookPools;

  /// Movement FX banks, per kind of section.
  final Map<SongSectionKind, List<String>> movePools;
  final List<String> groupIds;

  const SongGeneratorOptions({
    this.style = SongStyle.club,
    this.audacity = 3,
    this.seed = 1,
    required this.lookLayerId,
    this.moveLayerId,
    this.lookPools = const {},
    this.movePools = const {},
    this.groupIds = const [],
  });

  SongGeneratorOptions copyWith({
    SongStyle? style,
    int? audacity,
    int? seed,
    String? lookLayerId,
    String? moveLayerId,
    bool clearMoveLayer = false,
    Map<SongSectionKind, List<String>>? lookPools,
    Map<SongSectionKind, List<String>>? movePools,
    List<String>? groupIds,
  }) => SongGeneratorOptions(
    style: style ?? this.style,
    audacity: audacity ?? this.audacity,
    seed: seed ?? this.seed,
    lookLayerId: lookLayerId ?? this.lookLayerId,
    moveLayerId: clearMoveLayer ? null : (moveLayerId ?? this.moveLayerId),
    lookPools: lookPools ?? this.lookPools,
    movePools: movePools ?? this.movePools,
    groupIds: groupIds ?? this.groupIds,
  );
}

/// How restless a bank looks, guessed from its name and timing — banks carry
/// no tags, so this is a hint the user can overrule in the wizard.
enum BankEnergy { calm, medium, intense }

const _calmWords = ['slow', 'calm', 'chill', 'ambient', 'soft', 'wash', 'breath', 'pad', 'warm', 'idle', 'fade'];
const _intenseWords = ['strobe', 'flash', 'drop', 'hard', 'burst', 'peak', 'blast', 'rave', 'fast', 'chase', 'stab'];

BankEnergy bankEnergy(Bank bank) {
  final name = bank.name.toLowerCase();
  if (_intenseWords.any(name.contains) || bank.isBeatFlash) return BankEnergy.intense;
  if (_calmWords.any(name.contains)) return BankEnergy.calm;
  if (bank.ownTiming && bank.holdMs < 600) return BankEnergy.intense;
  if (bank.ownTiming && bank.holdMs > 3000) return BankEnergy.calm;
  return BankEnergy.medium;
}

/// A first guess at which banks suit which kind of section: calm ones for
/// intros, breaks and outros, intense ones for drops, the in-betweens for
/// builds. A kind left with nothing falls back to every light bank.
Map<SongSectionKind, List<String>> suggestLookPools(List<Bank> banks) {
  final lights = [for (final b in banks) if (!b.isMovementFx && b.sceneSlots.any((s) => s != null)) b];
  List<String> ids(bool Function(BankEnergy) test) => [for (final b in lights) if (test(bankEnergy(b))) b.id];
  List<String> orAll(List<String> picked) => picked.isNotEmpty ? picked : [for (final b in lights) b.id];
  final calm = orAll(ids((e) => e == BankEnergy.calm || e == BankEnergy.medium));
  return {
    SongSectionKind.intro: calm,
    SongSectionKind.build: orAll(ids((e) => e != BankEnergy.calm)),
    SongSectionKind.drop: orAll(ids((e) => e != BankEnergy.calm)),
    SongSectionKind.breakdown: calm,
    SongSectionKind.outro: calm,
    SongSectionKind.custom: orAll(ids((_) => true)),
  };
}

/// Movement banks for the kinds that move: every FX bank on builds and drops,
/// the calm-named ones elsewhere.
Map<SongSectionKind, List<String>> suggestMovePools(List<Bank> banks) {
  final fx = [for (final b in banks) if (b.isMovementFx) b];
  final calm = [for (final b in fx) if (bankEnergy(b) == BankEnergy.calm) b.id];
  final all = [for (final b in fx) b.id];
  return {
    SongSectionKind.intro: calm,
    SongSectionKind.build: all,
    SongSectionKind.drop: all,
    SongSectionKind.breakdown: calm,
    SongSectionKind.outro: calm,
    SongSectionKind.custom: all,
  };
}

/// Turns an analysis into a show: for each section, a look on the look layer
/// (changing every few bars inside a long one), and movement on the movement
/// layer for the kinds the style moves. The same options and seed give the
/// same show; a new seed gives another arrangement of the same banks.
SongShow generateSongShow({
  required SongShow base,
  required SongAnalysis analysis,
  required SongGeneratorOptions options,
  String Function()? newId,
}) {
  final id = newId ?? () => const Uuid().v4();
  final rnd = math.Random(options.seed);
  final cues = <SongCue>[];

  // Audacity 1 stretches the interval, 5 squeezes it.
  const factors = [2.0, 1.5, 1.0, 0.75, 0.5];
  final factor = factors[(options.audacity - 1).clamp(0, 4)];

  String? lastLook;
  String? lastMove;
  var moving = false;

  String? pick(List<String> pool, String? avoid) {
    if (pool.isEmpty) return null;
    if (pool.length == 1) return pool.first;
    final choices = [for (final p in pool) if (p != avoid) p];
    return choices[rnd.nextInt(choices.length)];
  }

  for (final section in analysis.sections) {
    if (!section.enabled) continue;
    final kind = section.kind;
    final bars = (section.lengthBeats / 4).round();

    // Look: a change at the start, then every `interval` bars in a long section.
    final lookPool = options.lookPools[kind] ?? options.lookPools[SongSectionKind.custom] ?? const <String>[];
    final baseInterval = switch (kind) {
      SongSectionKind.drop => options.style.baseBars,
      SongSectionKind.build => math.max(4, options.style.baseBars ~/ 2),
      _ => options.style.baseBars * 2,
    };
    final interval = math.max(4, ((baseInterval * factor) / 4).round() * 4);
    for (var bar = 0; bar < bars; bar += interval) {
      final bank = pick(lookPool, lastLook);
      if (bank == null) break;
      lastLook = bank;
      cues.add(SongCue(
        id: id(),
        atBeat: section.startBeat + bar * 4,
        layerId: options.lookLayerId,
        target: ProgramTarget(id: bank, isBank: true),
      ));
    }

    // Movement: one path per section of a moving kind; a stop when a moving
    // stretch is followed by one that stays still.
    final moveLayer = options.moveLayerId;
    if (moveLayer == null) continue;
    final movePool = options.movePools[kind] ?? const <String>[];
    if (options.style.movementKinds.contains(kind) && movePool.isNotEmpty) {
      final bank = pick(movePool, lastMove);
      if (bank != null) {
        lastMove = bank;
        moving = true;
        cues.add(SongCue(
          id: id(),
          atBeat: section.startBeat,
          layerId: moveLayer,
          target: ProgramTarget(id: bank, isBank: true),
        ));
      }
    } else if (moving) {
      moving = false;
      cues.add(SongCue(id: id(), atBeat: section.startBeat, layerId: moveLayer, action: SongCueAction.stop));
    }
  }

  return base.copyWith(
    origin: SongShowOrigin.auto,
    bpm: analysis.bpm,
    beatOffsetMs: analysis.beatOffsetMs,
    sections: analysis.sections,
    cues: cues,
    groupIds: options.groupIds,
  );
}

/// A show with the analysis's tempo, grid and sections but no cues — the
/// "apply tempo and sections only" choice.
SongShow applyAnalysis(SongShow base, SongAnalysis analysis) =>
    base.copyWith(bpm: analysis.bpm, beatOffsetMs: analysis.beatOffsetMs, sections: analysis.sections);

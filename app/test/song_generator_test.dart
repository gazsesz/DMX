import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/core/song/song_analysis.dart';
import 'package:dmx_controller/core/song/song_generator.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/song_show.dart';

SongAnalysis analysis() => const SongAnalysis(
  bpm: 128,
  beatOffsetMs: 120,
  tempoConfidence: 0.9,
  barLevel: [],
  barLow: [],
  sections: [
    SongSection(startBeat: 0, lengthBeats: 32, kind: SongSectionKind.intro),
    SongSection(startBeat: 32, lengthBeats: 32, kind: SongSectionKind.build),
    SongSection(startBeat: 64, lengthBeats: 128, kind: SongSectionKind.drop),
    SongSection(startBeat: 192, lengthBeats: 32, kind: SongSectionKind.breakdown),
    SongSection(startBeat: 224, lengthBeats: 32, kind: SongSectionKind.outro, enabled: false),
  ],
);

SongGeneratorOptions options({int seed = 1, int audacity = 3, SongStyle style = SongStyle.club, String? move = 'l2'}) =>
    SongGeneratorOptions(
      style: style,
      audacity: audacity,
      seed: seed,
      lookLayerId: 'l1',
      moveLayerId: move,
      lookPools: const {
        SongSectionKind.intro: ['calm1', 'calm2'],
        SongSectionKind.build: ['mid1', 'mid2'],
        SongSectionKind.drop: ['hot1', 'hot2', 'hot3'],
        SongSectionKind.breakdown: ['calm1', 'calm2'],
        SongSectionKind.outro: ['calm1'],
      },
      movePools: const {
        SongSectionKind.build: ['fx1'],
        SongSectionKind.drop: ['fx1', 'fx2'],
      },
    );

SongShow gen(SongGeneratorOptions o) {
  var n = 0;
  return generateSongShow(
    base: const SongShow(id: 's', name: 'Song'),
    analysis: analysis(),
    options: o,
    newId: () => 'c${n++}',
  );
}

void main() {
  test('copies tempo, grid and sections and marks the show automatic', () {
    final s = gen(options());
    expect(s.origin, SongShowOrigin.auto);
    expect(s.bpm, 128);
    expect(s.beatOffsetMs, 120);
    expect(s.sections, hasLength(5));
  });

  test('same seed, same show; another seed, another arrangement', () {
    final a = gen(options(seed: 7)).toJson();
    final b = gen(options(seed: 7)).toJson();
    expect(a, b);
    final others = [for (var seed = 8; seed < 14; seed++) gen(options(seed: seed)).toJson().toString()];
    expect(others.toSet().length, greaterThan(1), reason: 'seeds change the picks');
  });

  test('each section starts with a look from its own pool on the look layer', () {
    final s = gen(options());
    String lookAt(double beat) => s.cues.firstWhere((c) => c.layerId == 'l1' && c.atBeat == beat).target!.id;
    expect(['calm1', 'calm2'], contains(lookAt(0)));
    expect(['mid1', 'mid2'], contains(lookAt(32)));
    expect(['hot1', 'hot2', 'hot3'], contains(lookAt(64)));
    expect(['calm1', 'calm2'], contains(lookAt(192)));
  });

  test('a disabled section gets no cues', () {
    final s = gen(options());
    expect(s.cues.where((c) => c.atBeat >= 224), isEmpty);
  });

  test('a long drop changes its look and never repeats the previous look back to back', () {
    final s = gen(options(audacity: 3));
    final drop = [for (final c in s.cues) if (c.layerId == 'l1' && c.atBeat >= 64 && c.atBeat < 192) c];
    expect(drop.length, greaterThan(1));
    for (var i = 1; i < drop.length; i++) {
      expect(drop[i].target!.id, isNot(drop[i - 1].target!.id));
    }
  });

  test('more audacity means more changes', () {
    int changes(int a) => gen(options(audacity: a)).cues.where((c) => c.layerId == 'l1').length;
    expect(changes(5), greaterThan(changes(3)));
    expect(changes(3), greaterThan(changes(1)));
  });

  test('club moves on builds and drops and stops the movement for the break', () {
    final s = gen(options());
    final move = [for (final c in s.cues) if (c.layerId == 'l2') c]..sort((a, b) => a.atBeat.compareTo(b.atBeat));
    expect([for (final c in move) (c.atBeat, c.action)], [
      (32.0, SongCueAction.start),
      (64.0, SongCueAction.start),
      (192.0, SongCueAction.stop),
    ]);
  });

  test('rock moves on drops only, chill never, and no movement layer means no movement cues', () {
    expect(gen(options(style: SongStyle.rock)).cues.where((c) => c.layerId == 'l2').map((c) => c.atBeat), [64, 192]);
    expect(gen(options(style: SongStyle.chill)).cues.where((c) => c.layerId == 'l2'), isEmpty);
    expect(gen(options(move: null)).cues.where((c) => c.layerId == 'l2'), isEmpty);
  });

  test('banks are sorted into calm, medium and intense by name and timing', () {
    Bank bank(String id, String name, {bool beatFlash = false, bool own = false, int hold = 1200}) => Bank(
      id: id,
      name: name,
      sceneSlots: const ['s'],
      isBeatFlash: beatFlash,
      ownTiming: own,
      holdMs: hold,
    );
    expect(bankEnergy(bank('a', 'Slow wash blue')), BankEnergy.calm);
    expect(bankEnergy(bank('b', 'Strobe burst')), BankEnergy.intense);
    expect(bankEnergy(bank('c', 'Beat Flash', beatFlash: true)), BankEnergy.intense);
    expect(bankEnergy(bank('d', 'Rainbow', own: true, hold: 300)), BankEnergy.intense);
    expect(bankEnergy(bank('e', 'Rainbow', own: true, hold: 5000)), BankEnergy.calm);
    expect(bankEnergy(bank('f', 'Rainbow')), BankEnergy.medium);
  });

  test('suggested pools put calm banks in intros and intense ones in drops, and fall back to all banks', () {
    final banks = [
      const Bank(id: 'calm', name: 'Slow wash', sceneSlots: ['s']),
      const Bank(id: 'hot', name: 'Strobe', sceneSlots: ['s']),
      const Bank(id: 'empty', name: 'Empty', sceneSlots: [null]),
      Bank(id: 'fx', name: 'Circle', sceneSlots: const [], fx: const MovementFx()),
    ];
    final looks = suggestLookPools(banks);
    expect(looks[SongSectionKind.intro], ['calm']);
    expect(looks[SongSectionKind.drop], ['hot']);
    final onlyCalm = suggestLookPools([banks.first]);
    expect(onlyCalm[SongSectionKind.drop], ['calm'], reason: 'nothing intense: fall back to everything');
    expect(suggestMovePools(banks)[SongSectionKind.drop], ['fx']);
  });
}

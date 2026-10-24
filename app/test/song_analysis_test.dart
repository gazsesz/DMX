import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/core/song/song_analysis.dart';
import 'package:dmx_controller/models/song_show.dart';

const sr = 11025;

/// A synthetic track: [barPlan] says what each bar contains.
/// 'h' hats only (quiet), 'k' kick + hats + bass (loud), 'p' a pad (no pulse),
/// 'r' a riser (pad that grows, hats busier).
Float32List synth({required double bpm, required double offsetSec, required String barPlan, int seed = 1}) {
  final beat = 60 / bpm;
  final barSec = beat * 4;
  final total = offsetSec + barPlan.length * barSec + 1;
  final out = Float32List((total * sr).round());
  final rnd = math.Random(seed);

  void add(double at, double len, double Function(double t) f, double gain) {
    final start = (at * sr).round();
    final n = (len * sr).round();
    for (var i = 0; i < n && start + i < out.length; i++) {
      out[start + i] += (gain * f(i / sr)).toDouble();
    }
  }

  for (var bar = 0; bar < barPlan.length; bar++) {
    final kind = barPlan[bar];
    final barStart = offsetSec + bar * barSec;
    for (var b = 0; b < 4; b++) {
      final t = barStart + b * beat;
      if (kind == 'k') {
        add(t, 0.18, (x) => math.sin(2 * math.pi * 55 * x) * math.exp(-x * 22), 0.9);
        add(t, beat, (x) => math.sin(2 * math.pi * 41 * x), 0.2);
      }
      if (kind == 'h' || kind == 'k' || kind == 'r') {
        for (var e = 0; e < 2; e++) {
          add(t + e * beat / 2, 0.03, (x) => (rnd.nextDouble() * 2 - 1) * math.exp(-x * 90), kind == 'k' ? 0.35 : 0.16);
        }
      }
      if (kind == 'p' || kind == 'r') {
        final g = kind == 'r' ? 0.05 + 0.3 * (bar % 8 + b / 4) / 8 : 0.08;
        add(t, beat, (x) => math.sin(2 * math.pi * 1500 * x) * 0.5 + math.sin(2 * math.pi * 2300 * x) * 0.3, g);
      }
    }
  }
  return out;
}

/// Distance between two grid offsets, wrapping at one beat.
double offsetError(double aSec, double bSec, double beatSec) {
  var d = (aSec - bSec) % beatSec;
  if (d > beatSec / 2) d -= beatSec;
  return d.abs();
}

void main() {
  // 8 intro (hats), 8 build (riser), 16 drop, 8 break (pad), 16 drop, 8 outro.
  final plan = 'h' * 8 + 'r' * 8 + 'k' * 16 + 'p' * 8 + 'k' * 16 + 'h' * 8;

  test('finds the tempo and the beat grid of a steady track', () {
    final a = analyzeSong(synth(bpm: 128, offsetSec: 0.2, barPlan: plan), sr);
    expect(a.bpm, closeTo(128, 1.5));
    expect(offsetError(a.beatOffsetMs / 1000, 0.2, 60 / 128), lessThan(0.04));
    expect(a.tempoConfidence, greaterThan(0.2));
  });

  test('does not report double or half tempo', () {
    final slow = analyzeSong(synth(bpm: 100, offsetSec: 0, barPlan: 'k' * 24), sr);
    expect(slow.bpm, closeTo(100, 1.5));
    final fast = analyzeSong(synth(bpm: 150, offsetSec: 0, barPlan: 'k' * 24), sr);
    expect(fast.bpm, closeTo(150, 2));
  });

  test('puts section boundaries where the music changes and calls the loud parts drops', () {
    final a = analyzeSong(synth(bpm: 128, offsetSec: 0.2, barPlan: plan), sr);
    final drops = a.sections.where((s) => s.kind == SongSectionKind.drop).toList();
    expect(drops, hasLength(2), reason: '${a.sections.map((s) => '${s.startBeat / 4}+${s.lengthBeats / 4}:${s.kind.name}')}');
    // Bars 16-31 and 40-55, give or take a phrase edge.
    expect(drops[0].startBeat / 4, inInclusiveRange(14, 18));
    expect(drops[0].endBeat / 4, inInclusiveRange(30, 34));
    expect(drops[1].startBeat / 4, inInclusiveRange(38, 42));
    expect(a.sections.first.kind, SongSectionKind.intro);
    expect(a.sections.first.startBeat, 0);
    // Contiguous cover of the whole song.
    for (var i = 1; i < a.sections.length; i++) {
      expect(a.sections[i].startBeat, a.sections[i - 1].endBeat);
    }
  });

  test('a track too short to analyse comes back with defaults, not an error', () {
    final a = analyzeSong(Float32List(2000), sr);
    expect(a.bpm, 120);
    expect(a.sections, isEmpty);
  });

  test('segmentation labels a quiet stretch before a drop as a build and after it as a break', () {
    final level = [for (var i = 0; i < 48; i++) i < 12 ? 0.2 : (i < 16 ? 0.5 : (i < 32 ? 0.95 : (i < 40 ? 0.2 : 0.9)))];
    final sections = segmentSections(level, level);
    final kinds = sections.map((s) => s.kind).toList();
    expect(kinds, contains(SongSectionKind.drop));
    expect(kinds, contains(SongSectionKind.breakdown));
    expect(sections.first.kind, SongSectionKind.intro);
  });
}

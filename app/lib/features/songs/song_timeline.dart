import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart';

import '../../core/song/song_timeline_math.dart';
import '../../core/theme/app_colors.dart';
import '../../models/layer.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';

const timelineLabelWidth = 88.0;
const _rulerHeight = 24.0;
const _waveHeight = 64.0;
const _sectionHeight = 28.0;
const _laneHeight = 44.0;

const _layerColors = [Color(0xFF3B6FD4), Color(0xFF1F8A7A), Color(0xFF9A3BD4), Color(0xFFD4803B), Color(0xFFD43B6F)];

Color layerColor(int index) => _layerColors[index % _layerColors.length];

Color sectionColor(SongSectionKind kind) => switch (kind) {
  SongSectionKind.intro => const Color(0xFF475569),
  SongSectionKind.build => const Color(0xFF3B4A8A),
  SongSectionKind.drop => const Color(0xFF7C3A9A),
  SongSectionKind.breakdown => const Color(0xFF2A5A4A),
  SongSectionKind.outro => const Color(0xFF475569),
  SongSectionKind.custom => const Color(0xFF3F4756),
};

String sectionKindLabel(SongSectionKind kind) => switch (kind) {
  SongSectionKind.intro => 'Intro',
  SongSectionKind.build => 'Build',
  SongSectionKind.drop => 'Drop',
  SongSectionKind.breakdown => 'Break',
  SongSectionKind.outro => 'Outro',
  SongSectionKind.custom => 'Section',
};

/// The song's timeline: ruler, waveform, section ribbon and one lane per
/// layer, with a playhead. Pure drawing and gestures — the editor owns state.
class SongTimeline extends StatelessWidget {
  const SongTimeline({
    super.key,
    required this.show,
    required this.layers,
    required this.scale,
    required this.scrollController,
    required this.targetName,
    required this.snap,
    this.waveform,
    this.waveformBinsPerSecond = 20,
    this.playheadBeat,
    this.cursorBeat = 0,
    this.selectedCueId,
    this.onTapRuler,
    this.onTapLane,
    this.onTapCue,
    this.onMoveCue,
    this.onTapSection,
    this.onTapSectionRow,
  });

  final SongShow show;
  final List<Layer> layers;
  final TimelineScale scale;
  final ScrollController scrollController;
  final String Function(ProgramTarget? target) targetName;
  final SongSnap snap;
  final Float32List? waveform;
  final int waveformBinsPerSecond;

  /// The song position while playing, in beats; null when stopped.
  final ValueListenable<double?>? playheadBeat;

  /// Where playback will start from.
  final double cursorBeat;
  final String? selectedCueId;

  final void Function(double beat)? onTapRuler;
  final void Function(String layerId, double beat)? onTapLane;
  final void Function(SongCue cue)? onTapCue;
  final void Function(SongCue cue, double newBeat)? onMoveCue;
  final void Function(SongSection section)? onTapSection;
  final void Function(double beat)? onTapSectionRow;

  @override
  Widget build(BuildContext context) {
    final totalBeats = timelineBeats(show);
    final width = scale.x(totalBeats);
    final contentHeight = _rulerHeight + _waveHeight + _sectionHeight + layers.length * _laneHeight;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: timelineLabelWidth,
          child: Column(
            children: [
              const SizedBox(height: _rulerHeight + _waveHeight),
              const _LabelCell(height: _sectionHeight, text: 'Sections'),
              for (var i = 0; i < layers.length; i++)
                _LabelCell(height: _laneHeight, text: layers[i].name, color: layerColor(i)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: contentHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _GridPainter(scale: scale, totalBeats: totalBeats)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _rulerHeight,
                    child: GestureDetector(
                      key: const ValueKey('timeline-ruler'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => onTapRuler?.call(snap.apply(scale.beatAt(d.localPosition.dx))),
                      child: CustomPaint(painter: _RulerPainter(scale: scale, totalBeats: totalBeats)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _rulerHeight,
                    height: _waveHeight,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _WavePainter(
                          show: show,
                          scale: scale,
                          waveform: waveform,
                          binsPerSecond: waveformBinsPerSecond,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _rulerHeight + _waveHeight,
                    height: _sectionHeight,
                    child: _SectionRow(
                      show: show,
                      scale: scale,
                      snap: snap,
                      onTapSection: onTapSection,
                      onTapRow: onTapSectionRow,
                    ),
                  ),
                  for (var i = 0; i < layers.length; i++)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _rulerHeight + _waveHeight + _sectionHeight + i * _laneHeight,
                      height: _laneHeight,
                      child: _Lane(
                        key: ValueKey('lane-${layers[i].id}'),
                        show: show,
                        layerId: layers[i].id,
                        color: layerColor(i),
                        scale: scale,
                        snap: snap,
                        endBeat: totalBeats,
                        targetName: targetName,
                        selectedCueId: selectedCueId,
                        onTapLane: onTapLane,
                        onTapCue: onTapCue,
                        onMoveCue: onMoveCue,
                      ),
                    ),
                  Positioned(
                    left: scale.x(cursorBeat) - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const IgnorePointer(child: ColoredBox(color: AppColors.accent)),
                  ),
                  if (playheadBeat != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<double?>(
                          valueListenable: playheadBeat!,
                          builder: (context, beat, _) => beat == null
                              ? const SizedBox.shrink()
                              : Stack(
                                  children: [
                                    Positioned(
                                      left: scale.x(beat) - 1,
                                      top: 0,
                                      bottom: 0,
                                      width: 2,
                                      child: const ColoredBox(color: Colors.white),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabelCell extends StatelessWidget {
  const _LabelCell({required this.height, required this.text, this.color});
  final double height;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      children: [
        Container(width: 4, height: height - 12, color: color ?? Colors.transparent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ),
      ],
    ),
  );
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.show,
    required this.scale,
    required this.snap,
    this.onTapSection,
    this.onTapRow,
  });

  final SongShow show;
  final TimelineScale scale;
  final SongSnap snap;
  final void Function(SongSection section)? onTapSection;
  final void Function(double beat)? onTapRow;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          key: const ValueKey('timeline-sections'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onTapRow?.call(snap.apply(scale.beatAt(d.localPosition.dx))),
          child: const ColoredBox(color: Color(0x14FFFFFF)),
        ),
      ),
      for (final s in show.sections)
        Positioned(
          left: scale.x(s.startBeat) + 1,
          width: math.max(scale.x(s.lengthBeats) - 2, 8),
          top: 2,
          bottom: 2,
          child: GestureDetector(
            key: ValueKey('section-${s.startBeat}'),
            onTap: () => onTapSection?.call(s),
            child: Opacity(
              opacity: s.enabled ? 1 : 0.4,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: sectionColor(s.kind), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  s.label.isEmpty ? sectionKindLabel(s.kind) : s.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    decoration: s.enabled ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Lane extends StatelessWidget {
  const _Lane({
    super.key,
    required this.show,
    required this.layerId,
    required this.color,
    required this.scale,
    required this.snap,
    required this.endBeat,
    required this.targetName,
    required this.selectedCueId,
    this.onTapLane,
    this.onTapCue,
    this.onMoveCue,
  });

  final SongShow show;
  final String layerId;
  final Color color;
  final TimelineScale scale;
  final SongSnap snap;
  final double endBeat;
  final String Function(ProgramTarget? target) targetName;
  final String? selectedCueId;
  final void Function(String layerId, double beat)? onTapLane;
  final void Function(SongCue cue)? onTapCue;
  final void Function(SongCue cue, double newBeat)? onMoveCue;

  @override
  Widget build(BuildContext context) {
    final spans = cueSpans(show, layerId, endBeat);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey('lane-tap-$layerId'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => onTapLane?.call(layerId, snap.apply(scale.beatAt(d.localPosition.dx))),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
              ),
            ),
          ),
        ),
        for (final span in spans)
          _CueBlock(
            key: ValueKey('cue-${span.cue.id}'),
            span: span,
            color: color,
            scale: scale,
            snap: snap,
            label: targetName(span.cue.target),
            selected: span.cue.id == selectedCueId,
            muted: !(show.sectionAt(span.cue.atBeat)?.enabled ?? true),
            onTap: () => onTapCue?.call(span.cue),
            onMove: (beat) => onMoveCue?.call(span.cue, beat),
          ),
      ],
    );
  }
}

class _CueBlock extends StatefulWidget {
  const _CueBlock({
    super.key,
    required this.span,
    required this.color,
    required this.scale,
    required this.snap,
    required this.label,
    required this.selected,
    required this.muted,
    required this.onTap,
    required this.onMove,
  });

  final CueSpan span;
  final Color color;
  final TimelineScale scale;
  final SongSnap snap;
  final String label;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;
  final void Function(double beat) onMove;

  @override
  State<_CueBlock> createState() => _CueBlockState();
}

class _CueBlockState extends State<_CueBlock> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    final cue = widget.span.cue;
    final isStop = cue.action == SongCueAction.stop;
    final left = widget.scale.x(cue.atBeat) + _dx;
    final naturalWidth = widget.scale.x(widget.span.endBeat - cue.atBeat);
    final width = isStop ? 34.0 : math.max(naturalWidth - 2, 30.0);
    return Positioned(
      left: left,
      width: width,
      top: 4,
      bottom: 4,
      child: GestureDetector(
        onTap: widget.onTap,
        onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
        onHorizontalDragEnd: (_) {
          final moved = widget.snap.apply(widget.scale.beatAt(widget.scale.x(cue.atBeat) + _dx));
          setState(() => _dx = 0);
          if (moved != cue.atBeat) widget.onMove(moved);
        },
        onHorizontalDragCancel: () => setState(() => _dx = 0),
        child: Opacity(
          opacity: widget.muted ? 0.4 : 1,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isStop ? AppColors.panel2 : widget.color,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: widget.selected ? Colors.white : (isStop ? AppColors.textFaint : Colors.transparent),
                width: widget.selected ? 2 : 1,
              ),
            ),
            child: Text(
              isStop ? 'Stop' : widget.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.scale, required this.totalBeats});
  final TimelineScale scale;
  final double totalBeats;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Paint()..color = const Color(0x33FFFFFF);
    final beat = Paint()..color = const Color(0x14FFFFFF);
    final showBeats = scale.pixelsPerBeat >= 14;
    for (var b = 0; b <= totalBeats; b++) {
      final isBar = b % 4 == 0;
      if (!isBar && !showBeats) continue;
      final x = scale.x(b.toDouble());
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), isBar ? bar : beat);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.scale.pixelsPerBeat != scale.pixelsPerBeat || old.totalBeats != totalBeats;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.scale, required this.totalBeats});
  final TimelineScale scale;
  final double totalBeats;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.panel2);
    // Label every bar when there's room, otherwise every 4th/16th.
    final every = scale.pixelsPerBeat * 4 >= 36 ? 1 : (scale.pixelsPerBeat * 16 >= 36 ? 4 : 16);
    for (var bar = 0; bar * 4 <= totalBeats; bar += every) {
      final painter = TextPainter(
        text: TextSpan(text: '${bar + 1}', style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(scale.x(bar * 4.0) + 3, 5));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.scale.pixelsPerBeat != scale.pixelsPerBeat || old.totalBeats != totalBeats;
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.show, required this.scale, required this.waveform, required this.binsPerSecond});
  final SongShow show;
  final TimelineScale scale;
  final Float32List? waveform;
  final int binsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B0D12));
    final wave = waveform;
    if (wave == null || wave.isEmpty) return;
    var peak = 0.0;
    for (final v in wave) {
      peak = math.max(peak, v.abs());
    }
    if (peak <= 0) return;
    final paint = Paint()
      ..color = AppColors.accent2.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    final mid = size.height / 2;
    // One column per pixel: the loudest bin that falls into it.
    final binMs = 1000 / binsPerSecond;
    final startPx = math.max(0, scale.x(show.beatAtMs(0)).floor());
    final endPx = math.min(size.width.ceil(), scale.x(show.beatAtMs(wave.length * binMs)).ceil());
    for (var px = startPx; px < endPx; px++) {
      final fromBin = ((show.msOfBeat(scale.beatAt(px.toDouble()))) / binMs).floor();
      final toBin = ((show.msOfBeat(scale.beatAt(px + 1.0))) / binMs).ceil();
      var m = 0.0;
      for (var i = math.max(0, fromBin); i < math.min(wave.length, math.max(toBin, fromBin + 1)); i++) {
        m = math.max(m, wave[i].abs());
      }
      final h = (m / peak) * (mid - 2);
      canvas.drawLine(Offset(px + 0.5, mid - h), Offset(px + 0.5, mid + h), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.waveform != waveform ||
      old.scale.pixelsPerBeat != scale.pixelsPerBeat ||
      old.show.bpm != show.bpm ||
      old.show.beatOffsetMs != show.beatOffsetMs;
}

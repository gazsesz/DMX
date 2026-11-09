import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/song/cue_resize.dart';
import '../../core/song/song_timeline_math.dart';
import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';
import 'song_cue_block.dart';
import '../../l10n/l10n.dart';

/// One layer's lane on the timeline: its cue blocks, taps to add a cue, and
/// a long press on a look that lets a finger drag where it ends.
class SongLane extends StatefulWidget {
  const SongLane({
    super.key,
    required this.show,
    required this.layerId,
    required this.color,
    required this.scale,
    required this.snap,
    required this.endBeat,
    required this.cueName,
    required this.selectedCueId,
    this.onTapLane,
    this.onTapCue,
    this.onMoveCue,
    this.onResizeCue,
    this.isPinching,
  });

  final SongShow show;
  final String layerId;
  final Color color;
  final TimelineScale scale;
  final SongSnap snap;
  final double endBeat;
  final String Function(SongCue cue) cueName;
  final String? selectedCueId;
  final void Function(String layerId, double beat)? onTapLane;
  final void Function(SongCue cue)? onTapCue;
  final void Function(SongCue cue, double newBeat)? onMoveCue;

  /// A cue's end was dragged to a new beat (after a long press on it).
  final void Function(SongCue cue, double endBeat)? onResizeCue;

  /// True while two fingers pinch the timeline: cues ignore the touches.
  final bool Function()? isPinching;

  @override
  State<SongLane> createState() => _SongLaneState();
}

class _SongLaneState extends State<SongLane> {
  /// The cue whose end is being dragged after a long press, and where the
  /// finger has taken it so far.
  SongCue? _resizing;
  double _resizeEnd = 0;

  double _snapped(double localX) => widget.snap.apply(widget.scale.beatAt(localX));

  double _beatAtGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    return _snapped(box.globalToLocal(global).dx);
  }

  bool get _pinching => widget.isPinching?.call() ?? false;

  void _startResize(SongCue cue, double beat) {
    if (_pinching) return;
    if (cue.action == SongCueAction.stop) return;
    HapticFeedback.selectionClick();
    setState(() {
      _resizing = cue;
      _resizeEnd = math.max(beat, cue.atBeat + minCueBeats);
    });
  }

  void _moveResize(double beat) {
    final cue = _resizing;
    if (cue == null) return;
    setState(() => _resizeEnd = math.max(beat, cue.atBeat + minCueBeats));
  }

  void _endResize() {
    final cue = _resizing;
    final end = _resizeEnd;
    setState(() => _resizing = null);
    if (cue != null) widget.onResizeCue?.call(cue, end);
  }

  /// The start cue whose stretch covers [beat] on this lane, if any.
  SongCue? _cueCovering(double beat) {
    for (final span in cueSpans(widget.show, widget.layerId, widget.endBeat)) {
      if (span.cue.action == SongCueAction.start && beat >= span.cue.atBeat && beat < span.endBeat) {
        return span.cue;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final spans = cueSpans(widget.show, widget.layerId, widget.endBeat);
    final resizing = _resizing;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey('lane-tap-${widget.layerId}'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onTapLane?.call(widget.layerId, _snapped(d.localPosition.dx)),
            // Holding anywhere along a look picks that look up by its end.
            onLongPressStart: (d) {
              final cue = _cueCovering(widget.scale.beatAt(d.localPosition.dx));
              if (cue != null) _startResize(cue, _snapped(d.localPosition.dx));
            },
            onLongPressMoveUpdate: (d) => _moveResize(_snapped(d.localPosition.dx)),
            onLongPressEnd: (_) => _endResize(),
            onLongPressCancel: () => setState(() => _resizing = null),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
              ),
            ),
          ),
        ),
        for (final span in spans)
          SongCueBlock(
            key: ValueKey('cue-${span.cue.id}'),
            span: span,
            color: widget.color,
            scale: widget.scale,
            snap: widget.snap,
            label: widget.cueName(span.cue),
            selected: span.cue.id == widget.selectedCueId || span.cue.id == resizing?.id,
            muted: !(widget.show.sectionAt(span.cue.atBeat)?.enabled ?? true),
            onTap: () => widget.onTapCue?.call(span.cue),
            onMove: (beat) => widget.onMoveCue?.call(span.cue, beat),
            isLocked: () => _pinching,
            onLongPressStart: (global) => _startResize(span.cue, _beatAtGlobal(global)),
            onLongPressMove: (global) => _moveResize(_beatAtGlobal(global)),
            onLongPressEnd: _endResize,
            onLongPressCancel: () => setState(() => _resizing = null),
          ),
        if (resizing != null) _ResizeMarker(scale: widget.scale, startBeat: resizing.atBeat, endBeat: _resizeEnd),
      ],
    );
  }
}

/// While an end is being dragged: the stretch it would cover, a handle at the
/// end, and where that is.
class _ResizeMarker extends StatelessWidget {
  const _ResizeMarker({required this.scale, required this.startBeat, required this.endBeat});
  final TimelineScale scale;
  final double startBeat;
  final double endBeat;

  @override
  Widget build(BuildContext context) {
    final left = scale.x(startBeat);
    final right = scale.x(endBeat);
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            width: math.max(right - left, 2),
            top: 2,
            bottom: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white54),
              ),
            ),
          ),
          Positioned(
            left: right - 3,
            width: 6,
            top: 0,
            bottom: 0,
            child: const DecoratedBox(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(3))),
            ),
          ),
          Positioned(
            left: math.max(right - 110, left),
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text(
                context.l10n.songEndsBarBeat(endBeat ~/ 4 + 1, (endBeat % 4).floor() + 1),
                key: const ValueKey('resize-label'),
                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

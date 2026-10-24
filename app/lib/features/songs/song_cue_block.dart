import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/song/song_timeline_math.dart';
import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';

/// How much of a cue block, from its left edge, is the cue itself.
const cueHeadWidth = 96.0;

/// One cue on a lane: a head you tap (to change or delete it), drag (to move
/// it) or hold (to pick up its end), and a faded tail showing how long it
/// lasts. The tail lets taps through to the lane, so a Stop or another look
/// can be placed anywhere along it.
class SongCueBlock extends StatefulWidget {
  const SongCueBlock({
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
    required this.isLocked,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
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

  /// True while two fingers pinch the timeline: a drag then is the pinch.
  final bool Function() isLocked;

  /// A long press on the head, with the finger's position on screen.
  final void Function(Offset global) onLongPressStart;
  final void Function(Offset global) onLongPressMove;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  State<SongCueBlock> createState() => _SongCueBlockState();
}

class _SongCueBlockState extends State<SongCueBlock> {
  double _dx = 0;
  bool _pinchedDuringDrag = false;

  @override
  Widget build(BuildContext context) {
    final cue = widget.span.cue;
    final isStop = cue.action == SongCueAction.stop;
    final left = widget.scale.x(cue.atBeat) + _dx;
    final naturalWidth = widget.scale.x(widget.span.endBeat - cue.atBeat);
    final width = isStop ? 34.0 : math.max(naturalWidth - 2, 30.0);
    final headWidth = math.min(width, cueHeadWidth);
    final radius = BorderRadius.circular(5);
    return Positioned(
      left: left,
      width: width,
      top: 4,
      bottom: 4,
      child: Opacity(
        opacity: widget.muted ? 0.4 : 1,
        child: Stack(
          children: [
            if (width > headWidth)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.28), borderRadius: radius),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: headWidth,
              child: GestureDetector(
                key: ValueKey('cue-head-${cue.id}'),
                onTap: widget.onTap,
                onHorizontalDragUpdate: (d) {
                  if (widget.isLocked()) {
                    _pinchedDuringDrag = true;
                    return;
                  }
                  setState(() => _dx += d.delta.dx);
                },
                onHorizontalDragEnd: (_) {
                  if (_pinchedDuringDrag) {
                    _pinchedDuringDrag = false;
                    setState(() => _dx = 0);
                    return;
                  }
                  final moved = widget.snap.apply(widget.scale.beatAt(widget.scale.x(cue.atBeat) + _dx));
                  setState(() => _dx = 0);
                  if (moved != cue.atBeat) widget.onMove(moved);
                },
                onHorizontalDragCancel: () => setState(() => _dx = 0),
                onLongPressStart: isStop ? null : (d) => widget.onLongPressStart(d.globalPosition),
                onLongPressMoveUpdate: isStop ? null : (d) => widget.onLongPressMove(d.globalPosition),
                onLongPressEnd: isStop ? null : (_) => widget.onLongPressEnd(),
                onLongPressCancel: isStop ? null : widget.onLongPressCancel,
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: isStop ? (cue.stopBlackout ? Colors.black : AppColors.panel2) : widget.color,
                    borderRadius: radius,
                    border: Border.all(
                      color: widget.selected ? Colors.white : (isStop ? (cue.stopBlackout ? Colors.white54 : AppColors.textFaint) : Colors.transparent),
                      width: widget.selected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

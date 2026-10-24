import 'package:flutter/material.dart';

import '../../core/song/song_timeline_math.dart';

/// Whether a two-finger pinch is going on — so the timeline stops scrolling
/// and the cues stop reacting to the fingers while it lasts.
class PinchState extends ValueNotifier<bool> {
  PinchState() : super(false);
}

/// Zooms the timeline when two fingers pinch it, around the point between
/// them. One finger is left alone, so scrolling, tapping and dragging cues
/// work as before.
///
/// Built on raw pointer events rather than a scale gesture: a scale
/// recognizer would compete with the scroll view for single-finger drags.
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.scale,
    required this.controller,
    required this.onScale,
    required this.pinch,
    required this.child,
  });

  final TimelineScale scale;
  final ScrollController controller;
  final ValueChanged<TimelineScale> onScale;
  final PinchState pinch;
  final Widget child;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  final _pointers = <int, Offset>{};
  double _startDistance = 0;
  double _baseScale = 0;
  double _focalBeat = 0;

  Offset get _focal => (_pointers.values.first + _pointers.values.last) / 2;
  double get _distance => (_pointers.values.first - _pointers.values.last).distance;

  void _begin() {
    _startDistance = _distance;
    _baseScale = widget.scale.pixelsPerBeat;
    final offset = widget.controller.hasClients ? widget.controller.offset : 0.0;
    _focalBeat = (offset + _focal.dx) / _baseScale;
    widget.pinch.value = true;
  }

  void _update() {
    if (_startDistance < 8) return;
    final ppb = pinchPixelsPerBeat(_baseScale, _startDistance, _distance);
    if (ppb == widget.scale.pixelsPerBeat) return;
    widget.onScale(TimelineScale(ppb));
    final focalX = _focal.dx;
    // The scroll extent grows with the next layout, so move after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      if (!c.hasClients) return;
      final target = scrollOffsetForFocal(_focalBeat, focalX, ppb);
      c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent));
    });
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) _begin();
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) _update();
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) widget.pinch.value = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

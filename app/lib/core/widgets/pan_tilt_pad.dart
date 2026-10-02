import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/pan_tilt.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Another head drawn on the pad: where a fanned or individually-set head
/// in the same group actually sits, as a dashed ring.
class PadMarker {
  final PanTilt position;
  final String label;

  const PadMarker(this.position, this.label);
}

/// An XY pad for a moving head: across is pan, down is tilt, both over the
/// whole travel of the head (0-540°, 0-270°, or whatever the profile says).
///
/// Coarse mode is absolute: the head goes where you touch. Fine mode works
/// like a trackball: the handle stays in the middle, the grid scrolls under
/// your finger, and a full swipe across moves only a sixteenth of the range
/// — the precision a 16-bit head needs to land a beam on a mirror ball.
class PanTiltPad extends StatefulWidget {
  final PanTilt value;
  final List<PadMarker> markers;
  final int panRangeDeg;
  final int tiltRangeDeg;
  final bool fine;
  final ValueChanged<PanTilt> onChanged;

  const PanTiltPad({
    super.key,
    required this.value,
    required this.panRangeDeg,
    required this.tiltRangeDeg,
    required this.onChanged,
    this.markers = const [],
    this.fine = false,
  });

  /// How much of each axis the fine-mode view spans.
  static const fineFraction = 1 / 16;

  @override
  State<PanTiltPad> createState() => _PanTiltPadState();
}

/// Claims the drag the moment a finger lands, so the Scene editor's list
/// doesn't scroll away while a position is being set (same reasoning as the
/// channel faders' recognizer).
class _PadDragRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'pan/tilt pad drag';
}

class _PanTiltPadState extends State<PanTiltPad> {
  Size _size = Size.zero;
  PanTilt? _fineStart;
  Offset _fineAccum = Offset.zero;

  PanTilt _absoluteAt(Offset local) {
    if (_size.width <= 0 || _size.height <= 0) return widget.value;
    final x = (local.dx / _size.width).clamp(0.0, 1.0);
    final y = (local.dy / _size.height).clamp(0.0, 1.0);
    return PanTilt((x * PanTilt.max).round(), (y * PanTilt.max).round());
  }

  void _onStart(DragStartDetails details) {
    if (widget.fine) {
      _fineStart = widget.value;
      _fineAccum = Offset.zero;
    } else {
      widget.onChanged(_absoluteAt(details.localPosition));
    }
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.fine) {
      widget.onChanged(_absoluteAt(details.localPosition));
      return;
    }
    final start = _fineStart;
    if (start == null || _size.width <= 0 || _size.height <= 0) return;
    _fineAccum += details.delta;
    final pan = start.pan + _fineAccum.dx / _size.width * PanTilt.max * PanTiltPad.fineFraction;
    final tilt = start.tilt + _fineAccum.dy / _size.height * PanTilt.max * PanTiltPad.fineFraction;
    widget.onChanged(PanTilt(pan.round(), tilt.round()).clamped());
  }

  void _onEnd() => _fineStart = null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height = width * 0.72;
        _size = Size(width, height);
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _PadDragRecognizer: GestureRecognizerFactoryWithHandlers<_PadDragRecognizer>(
              _PadDragRecognizer.new,
              (recognizer) => recognizer
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = ((_) => _onEnd())
                ..onCancel = _onEnd,
            ),
          },
          child: Semantics(
            label: 'Pan and tilt pad',
            value: 'pan ${_panDegrees(widget.value.pan).round()}°, tilt ${_tiltDegrees(widget.value.tilt).round()}°',
            child: SizedBox(
              width: width,
              height: height,
              child: CustomPaint(
                painter: _PadPainter(
                  value: widget.value,
                  markers: widget.markers,
                  fine: widget.fine,
                  panRangeDeg: widget.panRangeDeg,
                  tiltRangeDeg: widget.tiltRangeDeg,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _panDegrees(int pan) => pan / PanTilt.max * widget.panRangeDeg;
  double _tiltDegrees(int tilt) => tilt / PanTilt.max * widget.tiltRangeDeg;
}

class _PadPainter extends CustomPainter {
  final PanTilt value;
  final List<PadMarker> markers;
  final bool fine;
  final int panRangeDeg;
  final int tiltRangeDeg;

  _PadPainter({
    required this.value,
    required this.markers,
    required this.fine,
    required this.panRangeDeg,
    required this.tiltRangeDeg,
  });

  /// The 16-bit window the pad currently shows on each axis.
  (double, double, double, double) get _window {
    if (!fine) return (0, PanTilt.max.toDouble(), 0, PanTilt.max.toDouble());
    const span = PanTilt.max * PanTiltPad.fineFraction;
    return (value.pan - span / 2, value.pan + span / 2, value.tilt - span / 2, value.tilt + span / 2);
  }

  Offset _toCanvas(PanTilt p, Size size) {
    final (panMin, panMax, tiltMin, tiltMax) = _window;
    return Offset(
      (p.pan - panMin) / (panMax - panMin) * size.width,
      (p.tilt - tiltMin) / (tiltMax - tiltMin) * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = AppColors.panel);
    canvas.save();
    canvas.clipRRect(rrect);

    final (panMin, panMax, tiltMin, tiltMax) = _window;
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFF323843)
      ..strokeWidth = 1.2;

    // Grid lines every 45° of pan and tilt (every 2.8°/1.4°-ish in fine mode
    // — a sixteenth of that), with the centre of travel drawn heavier.
    final panStep = PanTilt.max * (fine ? PanTiltPad.fineFraction / 4 : 45 / panRangeDeg);
    final tiltStep = PanTilt.max * (fine ? PanTiltPad.fineFraction / 4 : 45 / tiltRangeDeg);
    const centre = PanTilt.max / 2;
    for (var v = centre - ((centre - panMin) / panStep).floor() * panStep; v <= panMax; v += panStep) {
      final x = (v - panMin) / (panMax - panMin) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), (v - centre).abs() < 1 ? major : grid);
    }
    for (var v = centre - ((centre - tiltMin) / tiltStep).floor() * tiltStep; v <= tiltMax; v += tiltStep) {
      final y = (v - tiltMin) / (tiltMax - tiltMin) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), (v - centre).abs() < 1 ? major : grid);
    }

    final handle = _toCanvas(value, size);
    final cross = Paint()
      ..color = AppColors.accent2.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(handle.dx, 0), Offset(handle.dx, size.height), cross);
    canvas.drawLine(Offset(0, handle.dy), Offset(size.width, handle.dy), cross);

    final ghost = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // Heads bunched up near each other (a small fan) keep their rings but
    // only the first gets a name, so the labels don't pile into a smudge.
    final labelled = <Offset>[handle];
    for (final marker in markers) {
      final at = _toCanvas(marker.position, size);
      if ((at - handle).distance < 3) continue;
      _dashedCircle(canvas, at, 7, ghost);
      if (labelled.every((other) => (other - at).distance > 34)) {
        _label(canvas, marker.label, at + const Offset(9, -16), AppColors.textDim, 9);
        labelled.add(at);
      }
    }

    canvas.drawCircle(handle, 11, Paint()..color = AppColors.accent);
    canvas.drawCircle(handle, 4, Paint()..color = AppColors.accentOn);

    final panDeg = value.pan / PanTilt.max * panRangeDeg;
    final tiltDeg = value.tilt / PanTilt.max * tiltRangeDeg;
    if (fine) {
      _label(canvas, 'FINE ±${(panRangeDeg * PanTiltPad.fineFraction / 2).toStringAsFixed(1)}°', const Offset(8, 6),
          AppColors.accent2, 9.5);
    } else {
      _label(canvas, '0°', Offset(6, size.height - 16), AppColors.textFaint, 9.5);
      _label(canvas, '$panRangeDeg°', Offset(size.width - 34, size.height - 16), AppColors.textFaint, 9.5);
      _label(canvas, 'tilt 0°', const Offset(6, 5), AppColors.textFaint, 9.5);
    }
    _label(
      canvas,
      'pan ${panDeg.toStringAsFixed(fine ? 1 : 0)}° · tilt ${tiltDeg.toStringAsFixed(fine ? 1 : 0)}°',
      Offset(size.width / 2 - 52, 5),
      AppColors.textDim,
      9.5,
    );
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke,
    );
  }

  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint paint) {
    const dashes = 10;
    for (var i = 0; i < dashes; i++) {
      final start = i * 2 * 3.141592653589793 / dashes;
      canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), start, 3.141592653589793 / dashes, false, paint);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: appFontFamily, color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.value != value ||
      old.fine != fine ||
      old.markers.length != markers.length ||
      old.panRangeDeg != panRangeDeg ||
      old.tiltRangeDeg != tiltRangeDeg ||
      !_sameMarkers(old.markers, markers);

  static bool _sameMarkers(List<PadMarker> a, List<PadMarker> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].position != b[i].position || a[i].label != b[i].label) return false;
    }
    return true;
  }
}

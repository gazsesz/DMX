import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A labeled 0-255 DMX channel control styled like a real lighting-desk
/// fader: a vertical slot with a ridged cap, plus a live numeric readout.
/// Shared by the Scene editor and Manual Control screens — lay several out
/// in a [Wrap] to mimic a bank of physical faders.
class ChannelSliderTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  const ChannelSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          _VerticalFader(value: value, color: color, onChanged: onChanged),
          const SizedBox(height: 6),
          Text('$value', style: appMonoStyle(fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// A drag-to-adjust vertical fader painted to resemble a real lighting/audio
/// console fader: a dark slot with a ridged, rounded cap. Dragging anywhere
/// over the track raises/lowers the value.
class _VerticalFader extends StatefulWidget {
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final double height;
  final double width;

  const _VerticalFader({
    required this.value,
    required this.color,
    required this.onChanged,
    this.height = 128,
    this.width = 34,
  });

  @override
  State<_VerticalFader> createState() => _VerticalFaderState();
}

class _VerticalFaderState extends State<_VerticalFader> {
  double? _dragStartValue;
  double _dragAccum = 0;

  void _onPanStart(DragStartDetails details) {
    _dragStartValue = widget.value.toDouble();
    _dragAccum = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStartValue == null) return;
    // Dragging the full track height covers the full 0-255 range; up = more.
    _dragAccum -= details.delta.dy * (255 / (widget.height - 24));
    final next = (_dragStartValue! + _dragAccum).clamp(0.0, 255.0);
    widget.onChanged(next.round());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onDoubleTap: () => widget.onChanged(0),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: _FaderPainter(fraction: widget.value / 255, accentColor: widget.color),
        ),
      ),
    );
  }
}

class _FaderPainter extends CustomPainter {
  final double fraction;
  final Color accentColor;

  static const _capWidth = 30.0;
  static const _capHeight = 20.0;

  _FaderPainter({required this.fraction, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final travel = size.height - _capHeight;
    final capCenterY = _capHeight / 2 + travel * (1 - fraction);

    // A small accent dot above the slot identifies the channel's function
    // colour (dimmer/color/pan-tilt/etc), same convention as before.
    canvas.drawCircle(Offset(centerX, 4), 2.5, Paint()..color = accentColor);

    // The slot: a thin recessed groove the cap rides in.
    final slotRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(centerX - 2, 10, 4, size.height - 14),
      const Radius.circular(2),
    );
    canvas.drawRRect(slotRect, Paint()..color = AppColors.background);
    canvas.drawRRect(
      slotRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    // Soft glow behind the cap in the channel's accent colour, for at-a-
    // glance feedback without recolouring the (realistically neutral) cap.
    if (fraction > 0.02) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(centerX, capCenterY), width: _capWidth + 6, height: _capHeight + 6),
          const Radius.circular(8),
        ),
        Paint()
          ..color = accentColor.withValues(alpha: 0.25 + 0.35 * fraction)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // The cap itself: a dark, rounded, horizontally-ridged block like a real
    // fader knob, with a subtle vertical gradient for a 3D bevel.
    final capRect = Rect.fromCenter(center: Offset(centerX, capCenterY), width: _capWidth, height: _capHeight);
    final capRRect = RRect.fromRectAndRadius(capRect, const Radius.circular(4));

    canvas.drawRRect(
      capRRect.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(
      capRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.textDim.withValues(alpha: 0.9), AppColors.panel2, AppColors.panel],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(capRect),
    );
    canvas.drawRRect(
      capRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    // Grip ridges across the cap face.
    final ridgePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (final dy in [-5.0, -1.5, 2.0, 5.5]) {
      canvas.drawLine(
        Offset(capRect.left + 4, capCenterY + dy),
        Offset(capRect.right - 4, capCenterY + dy),
        ridgePaint,
      );
    }
    // Bright centre indicator line, like the highlight groove in a real cap.
    canvas.drawLine(
      Offset(capRect.left + 3, capCenterY),
      Offset(capRect.right - 3, capCenterY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _FaderPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.accentColor != accentColor;
}

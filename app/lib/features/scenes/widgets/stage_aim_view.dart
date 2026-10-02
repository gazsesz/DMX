import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/positions/group_positions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/group_position.dart';
import '../../../models/patched_fixture.dart';
import '../../../models/stage_plan.dart';

/// The stage plan seen from above, for aiming a group of movers: each head
/// sits where the Stage Layout put it and throws a beam to its own
/// crosshair. Drag the orange handle to move the whole group, drag a ring to
/// move one beam on its own, or tap anywhere to send the group there.
class StageAimView extends StatefulWidget {
  final List<PatchedFixture> fixtures;

  /// The rest of the rig, drawn faintly for reference.
  final List<PatchedFixture> otherFixtures;
  final StagePlan stage;
  final GroupPosition position;
  final Map<String, ResolvedPosition> resolved;
  final ValueChanged<GroupPosition> onChanged;

  const StageAimView({
    super.key,
    required this.fixtures,
    required this.otherFixtures,
    required this.stage,
    required this.position,
    required this.resolved,
    required this.onChanged,
  });

  @override
  State<StageAimView> createState() => _StageAimViewState();
}

/// Wins the drag on touch-down so the editor's list doesn't scroll while a
/// beam is being placed.
class _AimDragRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'stage aim drag';
}

class _StageAimViewState extends State<StageAimView> {
  Size _size = Size.zero;

  /// The head whose ring is being dragged, or null while the handle is.
  String? _draggingFixture;

  StagePoint _toStage(Offset local) =>
      StagePoint(local.dx / _size.width, local.dy / _size.height).clamped();

  Offset _toCanvas(StagePoint p) => Offset(p.x * _size.width, p.y * _size.height);

  void _onStart(DragStartDetails details) {
    final local = details.localPosition;
    String? hit;
    var best = 26.0;
    for (final fixture in widget.fixtures) {
      final target = widget.resolved[fixture.id]?.target;
      if (target == null) continue;
      final distance = (_toCanvas(target) - local).distance;
      if (distance < best) {
        best = distance;
        hit = fixture.id;
      }
    }
    // The handle sits on top of the rings in a point formation; prefer it
    // there, or the group could never be moved as one.
    final onHandle = (_toCanvas(widget.position.handle) - local).distance < 20;
    if (hit != null && !onHandle) {
      setState(() => _draggingFixture = hit);
      return;
    }
    setState(() => _draggingFixture = null);
    widget.onChanged(moveHandle(widget.position, _toStage(local)));
  }

  void _onUpdate(DragUpdateDetails details) {
    final point = _toStage(details.localPosition);
    final fixtureId = _draggingFixture;
    if (fixtureId == null) {
      widget.onChanged(moveHandle(widget.position, point));
    } else {
      widget.onChanged(widget.position.copyWith(aimOverrides: {...widget.position.aimOverrides, fixtureId: point}));
    }
  }

  void _onEnd() => setState(() => _draggingFixture = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 420.0;
        final aspect = (widget.stage.widthM / widget.stage.depthM).clamp(0.9, 2.2);
        final height = width / aspect;
        _size = Size(width, height);
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _AimDragRecognizer: GestureRecognizerFactoryWithHandlers<_AimDragRecognizer>(
              _AimDragRecognizer.new,
              (recognizer) => recognizer
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = ((_) => _onEnd())
                ..onCancel = _onEnd,
            ),
          },
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _StagePainter(
                fixtures: widget.fixtures,
                otherFixtures: widget.otherFixtures,
                stage: widget.stage,
                position: widget.position,
                resolved: widget.resolved,
                dragging: _draggingFixture,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StagePainter extends CustomPainter {
  final List<PatchedFixture> fixtures;
  final List<PatchedFixture> otherFixtures;
  final StagePlan stage;
  final GroupPosition position;
  final Map<String, ResolvedPosition> resolved;
  final String? dragging;

  _StagePainter({
    required this.fixtures,
    required this.otherFixtures,
    required this.stage,
    required this.position,
    required this.resolved,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(double x, double y) => Offset(x * size.width, y * size.height);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = AppColors.panel);
    canvas.save();
    canvas.clipRRect(rrect);

    // One line per metre.
    final grid = Paint()
      ..color = const Color(0xFF1E232A)
      ..strokeWidth = 1;
    for (var m = 1.0; m < stage.widthM; m++) {
      final x = m / stage.widthM * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var m = 1.0; m < stage.depthM; m++) {
      final y = m / stage.depthM * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    _text(canvas, 'UPSTAGE', Offset(size.width / 2, 8), AppColors.textFaint, 9, centered: true);
    _text(canvas, 'AUDIENCE', Offset(size.width / 2, size.height - 18), AppColors.textFaint, 9, centered: true);
    _text(
      canvas,
      '${stage.widthM.toStringAsFixed(stage.widthM % 1 == 0 ? 0 : 1)} × ${stage.depthM.toStringAsFixed(stage.depthM % 1 == 0 ? 0 : 1)} m',
      Offset(8, size.height - 18),
      AppColors.textFaint,
      9,
    );

    final targetPaint = Paint()
      ..color = AppColors.textDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final target in stage.targets) {
      final c = at(target.x, target.y);
      _dashedCircle(canvas, c, 12, targetPaint);
      _text(canvas, '${target.name} · ${target.heightM.toStringAsFixed(1)} m', c + const Offset(15, -6),
          AppColors.textDim, 9);
    }

    for (final fixture in otherFixtures) {
      canvas.drawCircle(
        at(fixture.layoutX, fixture.layoutY),
        8,
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Beams first, so heads and rings draw over them.
    for (final fixture in fixtures) {
      final r = resolved[fixture.id];
      final target = r?.target;
      if (target == null) continue;
      final from = at(fixture.layoutX, fixture.layoutY);
      final to = at(target.x, target.y);
      final colour = r!.reachable ? AppColors.accent2 : AppColors.danger;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = colour.withValues(alpha: 0.7)
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        to,
        22,
        Paint()
          ..shader = RadialGradient(colors: [colour.withValues(alpha: 0.45), colour.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: to, radius: 22)),
      );
    }

    for (final fixture in fixtures) {
      final c = at(fixture.layoutX, fixture.layoutY);
      canvas.drawCircle(c, 12, Paint()..color = AppColors.panel2);
      canvas.drawCircle(
        c,
        12,
        Paint()
          ..color = AppColors.accent2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _text(canvas, fixture.label, c + const Offset(0, 15), AppColors.text, 9, centered: true);
    }

    for (final fixture in fixtures) {
      final r = resolved[fixture.id];
      final target = r?.target;
      if (target == null) continue;
      final c = at(target.x, target.y);
      final own = position.aimOverrides.containsKey(fixture.id);
      final colour = !r!.reachable ? AppColors.danger : AppColors.accent;
      canvas.drawCircle(
        c,
        dragging == fixture.id ? 11 : 9,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = own ? 2.6 : 2,
      );
      canvas.drawCircle(c, 2.5, Paint()..color = colour);
    }

    final handle = at(position.handle.x, position.handle.y);
    canvas.drawCircle(handle, 8, Paint()..color = AppColors.accent);
    canvas.drawCircle(handle, 3, Paint()..color = AppColors.accentOn);
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke,
    );
  }

  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint paint) {
    const dashes = 12;
    for (var i = 0; i < dashes; i++) {
      final start = i * 2 * 3.141592653589793 / dashes;
      canvas.drawArc(Rect.fromCircle(center: centre, radius: radius), start, 3.141592653589793 / dashes, false, paint);
    }
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double size, {bool centered = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: appFontFamily,
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, centered ? at - Offset(painter.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(_StagePainter old) => true;
}

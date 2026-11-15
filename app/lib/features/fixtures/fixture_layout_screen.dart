import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../models/fixture_mounting.dart';
import '../../models/patched_fixture.dart';
import '../../state/fixture_providers.dart';
import '../../state/stage_providers.dart';
import 'fixture_mounting_sheet.dart';
import '../../l10n/l10n.dart';

/// A 2D stage plot seen from above: drag each patched fixture's icon to
/// where it physically sits on the truss/stage. Upstage is at the top, the
/// audience at the bottom.
///
/// The positions are what the Scene editor's stage view aims from, so a
/// moving head can also be tapped to say how it's rigged (height, which way
/// it faces) and to calibrate it.
class FixtureLayoutScreen extends ConsumerWidget {
  const FixtureLayoutScreen({super.key});

  Future<void> _editStageSize(BuildContext context, WidgetRef ref) async {
    final plan = ref.read(stagePlanProvider);
    final width = TextEditingController(text: plan.widthM.toStringAsFixed(1));
    final depth = TextEditingController(text: plan.depthM.toStringAsFixed(1));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(context.l10n.scStageSize),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.scTheRealSizeOf,
              style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
            ),
            TextField(
              controller: width,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.l10n.scWidthLeftToRight, suffixText: 'm'),
            ),
            TextField(
              controller: depth,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.l10n.scDepthBackToThe, suffixText: 'm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonSave)),
        ],
      ),
    );
    if (saved != true) return;
    double? parse(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    final w = parse(width);
    final d = parse(depth);
    if (w == null || d == null || w <= 0 || d <= 0) return;
    ref.read(stagePlanProvider.notifier).setSize(widthM: w, depthM: d);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref.watch(patchedFixturesProvider);
    final plan = ref.watch(stagePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.scStageLayout),
        actions: [
          TextButton.icon(
            onPressed: () => _editStageSize(context, ref),
            icon: const Icon(Icons.straighten, size: 18),
            label: Text('${_metres(plan.widthM)} × ${_metres(plan.depthM)} m'),
          ),
          if (fixtures.isNotEmpty)
            IconButton(
              tooltip: context.l10n.scArrangeInAGrid,
              icon: const Icon(Icons.auto_fix_high),
              onPressed: () {
                final notifier = ref.read(patchedFixturesProvider.notifier);
                final columns = (fixtures.length <= 4) ? 2 : (fixtures.length <= 9 ? 3 : 4);
                for (var i = 0; i < fixtures.length; i++) {
                  final row = i ~/ columns;
                  final col = i % columns;
                  final rows = (fixtures.length / columns).ceil();
                  final x = (col + 0.5) / columns;
                  final y = (row + 0.5) / rows;
                  notifier.setLayoutPosition(fixtures[i].id, x, y);
                }
              },
            ),
        ],
      ),
      body: fixtures.isEmpty
          ? Center(
              child: Text(context.l10n.scNoPatchedFixturesYet3, style: TextStyle(color: AppColors.textFaint)),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.scDragEachFixtureTo,
                    style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                        return Container(
                          width: canvasSize.width,
                          height: canvasSize.height,
                          decoration: BoxDecoration(
                            color: AppColors.panel,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Stack(
                            children: [
                              Center(
                                child: Text(
                                  context.l10n.stageHeader,
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.border,
                                    letterSpacing: 6,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 0,
                                right: 0,
                                child: Center(child: _EdgeLabel(context.l10n.scUpstage)),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 0,
                                right: 0,
                                child: Center(child: _EdgeLabel(context.l10n.scAudience)),
                              ),
                              for (final fixture in fixtures)
                                _DraggableFixtureIcon(
                                  key: ValueKey(fixture.id),
                                  fixture: fixture,
                                  canvasSize: canvasSize,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _metres(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
}

class _EdgeLabel extends StatelessWidget {
  final String text;

  const _EdgeLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.textFaint),
    );
  }
}

class _DraggableFixtureIcon extends ConsumerStatefulWidget {
  final PatchedFixture fixture;
  final Size canvasSize;

  const _DraggableFixtureIcon({super.key, required this.fixture, required this.canvasSize});

  @override
  ConsumerState<_DraggableFixtureIcon> createState() => _DraggableFixtureIconState();
}

/// The lamp follows the finger from where the drag started (absolute, not
/// by summing per-event deltas against a position that may be a frame
/// stale), shows its spot locally while dragging, and only writes it to
/// the patch when the finger lifts — every patch change re-runs the DMX
/// output's channel scan, which was what made dragging lag behind.
class _DraggableFixtureIconState extends ConsumerState<_DraggableFixtureIcon> {
  Offset? _dragStartGlobal;
  Offset? _dragStartPos;
  Offset? _dragPos;

  Size get _canvas => widget.canvasSize;

  void _onPanStart(DragStartDetails details) {
    _dragStartGlobal = details.globalPosition;
    _dragStartPos = Offset(widget.fixture.layoutX, widget.fixture.layoutY);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final start = _dragStartPos;
    final startGlobal = _dragStartGlobal;
    if (start == null || startGlobal == null || _canvas.width <= 0 || _canvas.height <= 0) return;
    final moved = details.globalPosition - startGlobal;
    setState(() {
      _dragPos = Offset(
        (start.dx + moved.dx / _canvas.width).clamp(0.0, 1.0),
        (start.dy + moved.dy / _canvas.height).clamp(0.0, 1.0),
      );
    });
  }

  void _onPanEnd() {
    final pos = _dragPos;
    if (pos != null) {
      ref.read(patchedFixturesProvider.notifier).setLayoutPosition(widget.fixture.id, pos.dx, pos.dy);
    }
    setState(() {
      _dragPos = null;
      _dragStartPos = null;
      _dragStartGlobal = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final canvasSize = _canvas;
    const iconSize = 52.0;
    final x = _dragPos?.dx ?? fixture.layoutX;
    final y = _dragPos?.dy ?? fixture.layoutY;
    final maxLeft = (canvasSize.width - iconSize).clamp(0.0, double.infinity);
    final maxTop = (canvasSize.height - iconSize).clamp(0.0, double.infinity);
    final left = (x * canvasSize.width - iconSize / 2).clamp(0.0, maxLeft);
    final top = (y * canvasSize.height - iconSize / 2).clamp(0.0, maxTop);
    final color = fixtureCategoryColor(fixture.profile.category);
    final isMover = fixture.profile.channels.any((c) => c.function.isPanTilt);
    final mounting = fixture.mounting;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: isMover ? () => showFixtureMountingSheet(context, fixture.id) : null,
        // Count the movement from the touch-down point, so the first few
        // pixels the gesture needs to recognise a drag aren't lost.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: _onPanEnd,
        child: SizedBox(
          width: iconSize + 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: AppColors.panel2,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
                      ),
                      child: Icon(fixtureCategoryIcon(fixture.profile.category), color: color, size: 22),
                    ),
                    // Which way pan centre points: 0° straight down the plan
                    // towards the audience. Facing angles turn towards
                    // stage-plan right, which on screen is anticlockwise.
                    if (isMover)
                      Positioned.fill(
                        child: Transform.rotate(
                          angle: -mounting.facingDeg * math.pi / 180,
                          child: const Align(
                            alignment: Alignment.bottomCenter,
                            child: Icon(Icons.arrow_drop_down, size: 22, color: AppColors.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  fixture.label,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (isMover)
                Text(
                  '${mounting.mount == MountKind.hanging ? '↓' : '↑'} ${mounting.heightM.toStringAsFixed(1)} m'
                  '${mounting.isCalibrated ? ' · cal' : ''}',
                  style: const TextStyle(fontSize: 8.5, color: AppColors.textDim),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

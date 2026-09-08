import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../models/patched_fixture.dart';
import '../../state/fixture_providers.dart';

/// A free-form 2D stage plot: drag each patched fixture's icon to roughly
/// match where it physically sits on the truss/stage. Purely visual —
/// positions are just saved on the fixture for reference.
class FixtureLayoutScreen extends ConsumerWidget {
  const FixtureLayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref.watch(patchedFixturesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage Layout'),
        actions: [
          if (fixtures.isNotEmpty)
            IconButton(
              tooltip: 'Arrange in a grid',
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
          ? const Center(
              child: Text('No patched fixtures yet — patch one in the Templates tab', style: TextStyle(color: AppColors.textFaint)),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
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
                            'STAGE',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: AppColors.border,
                              letterSpacing: 6,
                            ),
                          ),
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
    );
  }
}

class _DraggableFixtureIcon extends ConsumerWidget {
  final PatchedFixture fixture;
  final Size canvasSize;

  const _DraggableFixtureIcon({super.key, required this.fixture, required this.canvasSize});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const iconSize = 52.0;
    final maxLeft = (canvasSize.width - iconSize).clamp(0.0, double.infinity);
    final maxTop = (canvasSize.height - iconSize).clamp(0.0, double.infinity);
    final left = (fixture.layoutX * canvasSize.width - iconSize / 2).clamp(0.0, maxLeft);
    final top = (fixture.layoutY * canvasSize.height - iconSize / 2).clamp(0.0, maxTop);
    final color = fixtureCategoryColor(fixture.profile.category);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) {
          if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
          final newX = (left + details.delta.dx + iconSize / 2) / canvasSize.width;
          final newY = (top + details.delta.dy + iconSize / 2) / canvasSize.height;
          ref.read(patchedFixturesProvider.notifier).setLayoutPosition(fixture.id, newX, newY);
        },
        child: SizedBox(
          width: iconSize + 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ),
      ),
    );
  }
}

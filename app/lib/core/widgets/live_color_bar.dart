import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/color_override_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../theme/app_colors.dart';

/// The Colour strip: basic colours to lay over whatever the scenes are playing.
///
/// A tap overrides the colour channels (RGB emitters, or the nearest slot of a
/// colour wheel) on the whole rig — or on one saved group — and "Scene" gives
/// the scenes their own colours back. Nothing in a bank or scene is changed.
class LiveColorBar extends ConsumerWidget {
  const LiveColorBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveColorProvider);
    final controller = ref.read(liveColorProvider.notifier);
    final groups = ref.watch(fixtureGroupsProvider);
    final groupName = [for (final g in groups) if (g.id == live.groupId) g.name].firstOrNull;

    return Material(
      color: AppColors.panel2,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Tooltip(
              message: 'Colour override — over the scenes',
              child: Icon(Icons.palette_outlined, size: 16, color: live.active ? AppColors.accent : AppColors.accent2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _AutoChip(active: !live.active, onTap: controller.auto),
                    const SizedBox(width: 6),
                    for (final color in liveColors)
                      _Swatch(
                        color: color,
                        selected: live.color?.id == color.id,
                        onTap: () => live.color?.id == color.id
                            ? controller.auto()
                            : controller.set(color, groupId: live.groupId),
                      ),
                  ],
                ),
              ),
            ),
            if (groups.isNotEmpty)
              PopupMenuButton<String?>(
                tooltip: 'Which fixtures the colour goes to',
                initialValue: live.groupId,
                onSelected: (id) => controller.setGroup(id == '' ? null : id),
                itemBuilder: (_) => [
                  const PopupMenuItem<String?>(value: '', child: Text('All fixtures')),
                  for (final group in groups) PopupMenuItem<String?>(value: group.id, child: Text(group.name)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        groupName ?? 'All',
                        style: TextStyle(fontSize: 11.5, color: groupName == null ? AppColors.textFaint : AppColors.accent),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textFaint),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutoChip extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _AutoChip({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: active ? AppColors.accent : AppColors.border, width: active ? 2 : 1.5),
        ),
        child: Text(
          'Auto',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? AppColors.accent : AppColors.textDim),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final LiveColor color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.swatch,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.text : AppColors.border, width: selected ? 3 : 1.5),
              boxShadow: selected ? [BoxShadow(color: color.swatch.withValues(alpha: 0.5), blurRadius: 8)] : null,
            ),
          ),
        ),
      ),
    );
  }
}

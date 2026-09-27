import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One color per layer position, the same everywhere a layer is shown, so
/// "L2" on the Dashboard, in a chase and in a Smart Program is recognisably
/// the same lane at a glance.
Color layerColor(int index) => const [
  AppColors.accent2,
  AppColors.accent,
  Color(0xFFA78BFA),
  Color(0xFF4ADE80),
  Color(0xFFF472B6),
][index < 0 ? 0 : index % 5];

/// The small "L1"/"L2" tag.
class LayerBadge extends StatelessWidget {
  final int index;
  final bool dim;
  final bool small;

  const LayerBadge({super.key, required this.index, this.dim = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = dim ? AppColors.textFaint : layerColor(index);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 4 : 6, vertical: small ? 0 : 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'L${index < 0 ? 1 : index + 1}',
        style: TextStyle(fontSize: small ? 9 : 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

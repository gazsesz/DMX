import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Preset icons offered when naming a group — deliberately a short, fixed
/// list rather than a full icon picker, since a group is almost always one
/// of these shapes (a stage position, the moving heads, an FX cue).
const List<String> fixtureGroupIconKeys = ['front', 'back', 'moving', 'fx', 'star', 'all'];

IconData fixtureGroupIcon(String iconKey) {
  switch (iconKey) {
    case 'front':
      return Icons.arrow_downward;
    case 'back':
      return Icons.arrow_upward;
    case 'moving':
      return Icons.highlight_outlined;
    case 'fx':
      return Icons.bolt;
    case 'star':
      return Icons.star_outline;
    default:
      return Icons.grid_view_outlined;
  }
}

Color fixtureGroupColor(String iconKey) {
  switch (iconKey) {
    case 'front':
    case 'moving':
      return AppColors.accent;
    case 'back':
      return AppColors.accent2;
    case 'fx':
      return AppColors.danger;
    default:
      return AppColors.textDim;
  }
}

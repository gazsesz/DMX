import 'package:flutter/material.dart';

import '../../models/fixture_profile.dart';
import '../theme/app_colors.dart';

IconData fixtureCategoryIcon(FixtureCategory category) {
  switch (category) {
    case FixtureCategory.movingHead:
      return Icons.highlight_outlined;
    case FixtureCategory.rgb:
      return Icons.lightbulb_outline;
    case FixtureCategory.generic:
      return Icons.edit_outlined;
  }
}

Color fixtureCategoryColor(FixtureCategory category) {
  switch (category) {
    case FixtureCategory.movingHead:
      return AppColors.accent;
    case FixtureCategory.rgb:
      return AppColors.accent2;
    case FixtureCategory.generic:
      return AppColors.textDim;
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Placeholder for a section that has a reviewed wireframe but no
/// implementation yet.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const ComingSoonScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(
              'Coming soon',
              style: TextStyle(color: AppColors.textFaint, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

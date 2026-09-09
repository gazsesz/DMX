import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../shell/app_shell.dart';

/// A brief branded launch screen shown while the app boots, before handing
/// off to AppShell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, __, ___) => const AppShell(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.tune, size: 40, color: Colors.black87),
                ),
                const SizedBox(height: 22),
                const Text(
                  'DMX CONTROLLER',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  'ART-NET LIGHTING CONTROL',
                  style: appMonoStyle(fontSize: 10, color: AppColors.textFaint).copyWith(letterSpacing: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

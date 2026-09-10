import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/project_snapshot.dart';
import '../../core/storage/project_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/remote_providers.dart';
import '../shell/app_shell.dart';

/// A brief branded launch screen shown while the app boots, before handing
/// off to AppShell — also where the most recently saved project is loaded,
/// so it's applied to every provider before any main-tab screen ever mounts
/// (avoids the same "TextEditingController snapshot a stale initial value"
/// race that settings loading has to avoid).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final minimumSplash = Future<void>.delayed(const Duration(milliseconds: 1300));
    await _loadLastProject();
    await _connectToNode();
    // Bring the remote-control endpoint up before the UI, so a watch macro
    // fired straight away already has something listening.
    await applyRemoteControlSetting(ref.read);
    await minimumSplash;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _loadLastProject() async {
    try {
      final files = await ProjectStorage().list();
      if (files.isEmpty) return;
      final builtIns = ref.read(fixtureLibraryProvider).where((f) => f.isBuiltIn).toList();
      final data = await ProjectStorage().loadFile(files.first.file, builtIns: builtIns);
      applyProjectData(ref, data);
    } catch (_) {
      // A missing/corrupt last project shouldn't block startup — the app
      // just opens with an empty/default show, same as a fresh install.
    }
  }

  /// Opens the Art-Net socket with whatever host the loaded project/settings
  /// ended up with, so triggers work straight away instead of greeting the
  /// user with "Not connected — check Settings" on the first tap.
  Future<void> _connectToNode() async {
    try {
      await ref.read(artNetServiceProvider).connect(ref.read(artNetSettingsProvider));
    } catch (_) {
      // Node not on the network yet (or Wi-Fi still coming up) — the
      // Settings screen's Test button is there for a manual retry.
    }
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
                const SizedBox(height: 10),
                Text(
                  'by Gazsesz',
                  style: appMonoStyle(fontSize: 11, color: AppColors.accent).copyWith(letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

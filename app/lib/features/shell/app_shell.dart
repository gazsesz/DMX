import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/playback_providers.dart';
import '../banks/banks_screen.dart';
import '../chases/chases_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../files/files_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../scenes/scenes_screen.dart';
import '../settings/settings_screen.dart';

/// Tablet layout kicks in above this width (matches the reviewed wireframes'
/// side-nav-rail breakpoint).
const _tabletBreakpoint = 700.0;

const _dashboardSectionIndex = 0;

class _NavSection {
  final String label;
  final IconData icon;
  final Widget screen;

  const _NavSection({required this.label, required this.icon, required this.screen});
}

final _sections = [
  const _NavSection(label: 'Home', icon: Icons.dashboard_outlined, screen: DashboardScreen()),
  const _NavSection(label: 'Files', icon: Icons.folder_outlined, screen: FilesScreen()),
  const _NavSection(label: 'Fixture', icon: Icons.lightbulb_outline, screen: FixturesScreen()),
  const _NavSection(label: 'Scene', icon: Icons.auto_awesome_mosaic_outlined, screen: ScenesScreen()),
  const _NavSection(label: 'Bank', icon: Icons.grid_view_outlined, screen: BanksScreen()),
  const _NavSection(label: 'Chase', icon: Icons.fast_forward_outlined, screen: ChasesScreen()),
  const _NavSection(label: 'Setup', icon: Icons.settings_outlined, screen: SettingsScreen()),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0; // Dashboard by default.

  void _select(int value) {
    setState(() => _index = value);
    ref.read(activeSectionIndexProvider.notifier).state = value;
  }

  Widget _buildNowPlayingBanner() {
    final nowPlaying = ref.watch(nowPlayingProvider);
    if (nowPlaying == null || _index == _dashboardSectionIndex) return const SizedBox.shrink();
    return Material(
      color: AppColors.panel2,
      // The OS status bar (clock/battery/notification icons) can sit right
      // on top of this banner on phones without a safe-area inset — SafeArea
      // pushes it below that, and centering the row keeps the readable text
      // away from the corners where those icons live either way.
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => _select(_dashboardSectionIndex),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PulsingDot(),
                const SizedBox(width: 8),
                Icon(
                  switch (nowPlaying.kind) {
                    PlaybackKind.bank => Icons.grid_view_outlined,
                    PlaybackKind.chase => Icons.fast_forward_outlined,
                    PlaybackKind.smartProgram => Icons.auto_graph,
                  },
                  size: 15,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Running: ${nowPlaying.name} — tap to return to Dashboard',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= _tabletBreakpoint;
        if (isTablet) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final section in _sections)
                      NavigationRailDestination(
                        icon: Icon(section.icon),
                        label: Text(section.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _buildNowPlayingBanner(),
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: [for (final section in _sections) section.screen],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              _buildNowPlayingBanner(),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [for (final section in _sections) section.screen],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final section in _sections)
                NavigationDestination(icon: Icon(section.icon), label: section.label),
            ],
          ),
        );
      },
    );
  }
}

/// A small pulsing dot marking the now-playing banner as live.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({super.key});

  @override
  State<_PulsingDot> createState() => __PulsingDotState();
}

class __PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: const Icon(Icons.circle, size: 8, color: AppColors.accent),
    );
  }
}

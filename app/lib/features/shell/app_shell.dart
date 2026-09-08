import 'package:flutter/material.dart';

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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // Dashboard by default.

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
                  onDestinationSelected: (value) => setState(() => _index = value),
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
                  child: IndexedStack(
                    index: _index,
                    children: [for (final section in _sections) section.screen],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [for (final section in _sections) section.screen],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
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

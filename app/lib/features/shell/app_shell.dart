import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/control_dock.dart';
import '../../models/control_dock_prefs.dart';
import '../../state/control_dock_providers.dart';
import '../../state/playback_providers.dart';
import '../banks/banks_screen.dart';
import '../chases/chases_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../files/files_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../manual_control/manual_control_screen.dart';
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
  const _NavSection(label: 'Live', icon: Icons.tune, screen: ManualControlScreen()),
  const _NavSection(label: 'Files', icon: Icons.folder_outlined, screen: FilesScreen()),
  const _NavSection(label: 'Fixture', icon: Icons.lightbulb_outline, screen: FixturesScreen()),
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

  /// The tab content with the docks around it — outside the IndexedStack, so
  /// they stay put across tabs. The Live Stage strip always sits along the
  /// bottom of the content; the control dock then takes the outermost edge
  /// the user picked for it.
  ///
  /// The dock is always present: it holds the only copy of the tempo and
  /// beat controls now, and a control you can lose is worse than a strip of
  /// edge. Its panel opens *over* the content rather than squeezing it —
  /// reflowing a bank grid while you're reaching into it is disorienting.
  ///
  /// Open, the dock grows into [ExpandedControlDock] in the strip's place
  /// rather than a sheet laid over it: the strip's buttons come along, as a
  /// rail down the panel's side. The strip isn't drawn underneath as well —
  /// one set of Stop/Blackout buttons, not two.
  Widget _withDocks(Widget content) {
    final dock = ref.watch(controlDockProvider);
    var body = content;
    if (dock.stageVisible) {
      body = Column(children: [Expanded(child: body), const LiveStageDock()]);
    }
    // Stretched across its edge, not sized to its buttons: a strip that
    // stops where the last button does reads as a floating island rather
    // than as the app's dock.
    final bar = [if (!dock.expanded) ControlDock(position: dock.position)];
    final withBar = switch (dock.position) {
      ControlDockPosition.bottom => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: body), ...bar],
      ),
      ControlDockPosition.right => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: body), ...bar],
      ),
    };

    // One shape whether the panel is open or shut, and the content always
    // the Stack's first child. Swapping between a Column and a Stack here
    // rebuilt everything below from scratch every time the panel opened or
    // closed: the rig kept running, but each screen lost what it knew about
    // the show — which slot was lit, which zone a smart program was in — so
    // the Dashboard sat there looking idle mid-song.
    return Stack(
      children: [
        Positioned.fill(child: withBar),
        // Tapping the page behind puts the panel away, the way any sheet
        // behaves. No scrim: you're reading levels off the rig, not a form.
        if (dock.expanded) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(controlDockProvider.notifier).collapse(),
              child: const SizedBox.shrink(),
            ),
          ),
          _panelFor(dock.position),
        ],
      ],
    );
  }

  /// The open dock, floated off the edge it docks to.
  ///
  /// Inset on every side rather than edge-to-edge: full-bleed it read as a
  /// new page rather than as a panel belonging to the dock, and there was
  /// nothing to tell you the dock was what you'd opened.
  Widget _panelFor(ControlDockPosition position) {
    final size = MediaQuery.sizeOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final narrow = size.width < _tabletBreakpoint;
    const panel = ExpandedControlDock();

    // On a phone a side panel would leave nothing beside it, so the same
    // content comes up from the bottom instead.
    if (narrow) {
      return Positioned(
        left: 8,
        right: 8,
        bottom: 8 + safeBottom,
        height: (size.height * 0.78).clamp(320.0, size.height - 24),
        child: panel,
      );
    }
    return switch (position) {
      ControlDockPosition.right => Positioned(
        top: 10,
        bottom: 10 + safeBottom,
        right: 10,
        width: 460,
        child: panel,
      ),
      ControlDockPosition.bottom => Positioned(
        right: 10,
        bottom: 10 + safeBottom,
        width: (size.width - 20).clamp(320.0, 640.0),
        height: (size.height * 0.8).clamp(320.0, 520.0),
        child: panel,
      ),
    };
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
                      Expanded(
                        child: _withDocks(
                          IndexedStack(
                            index: _index,
                            children: [for (final section in _sections) section.screen],
                          ),
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
              Expanded(
                child: _withDocks(
                  IndexedStack(
                    index: _index,
                    children: [for (final section in _sections) section.screen],
                  ),
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

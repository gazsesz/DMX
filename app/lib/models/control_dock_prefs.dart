/// Where the always-on-screen control dock lives. It sits outside the tab
/// content, so the live controls stay reachable from every screen.
enum ControlDockPosition {
  bottom,
  right;

  String get label => switch (this) {
    ControlDockPosition.bottom => 'Bottom',
    ControlDockPosition.right => 'Right side',
  };
}

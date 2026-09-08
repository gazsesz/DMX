/// How the Dashboard's Quick Triggers are arranged.
enum TriggerLayout { mosaic, list }

/// Size of each Quick Trigger tile in mosaic layout.
enum DashboardBoxSize { s, m, l, xl }

extension DashboardBoxSizeX on DashboardBoxSize {
  double get extent => switch (this) {
    DashboardBoxSize.s => 84,
    DashboardBoxSize.m => 130,
    DashboardBoxSize.l => 190,
    DashboardBoxSize.xl => 260,
  };

  String get label => switch (this) {
    DashboardBoxSize.s => 'S',
    DashboardBoxSize.m => 'M',
    DashboardBoxSize.l => 'L',
    DashboardBoxSize.xl => 'XL',
  };

  double get kindFontSize => switch (this) {
    DashboardBoxSize.s => 8,
    DashboardBoxSize.m => 9,
    DashboardBoxSize.l => 10,
    DashboardBoxSize.xl => 11,
  };

  double get nameFontSize => switch (this) {
    DashboardBoxSize.s => 11,
    DashboardBoxSize.m => 14,
    DashboardBoxSize.l => 18,
    DashboardBoxSize.xl => 22,
  };

  double get subFontSize => switch (this) {
    DashboardBoxSize.s => 8.5,
    DashboardBoxSize.m => 9.5,
    DashboardBoxSize.l => 10.5,
    DashboardBoxSize.xl => 11.5,
  };
}

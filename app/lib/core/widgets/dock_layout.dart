/// How the closed dock strip decides what it can show.
///
/// The strip used to scroll sideways when its controls didn't fit, which
/// looks harmless and isn't: on a tablet stood upright the panel button and
/// half of Blackout sat off the edge of the screen, and nothing said so.
/// Mid-show you don't discover a control by swiping for it.
///
/// So the strip wraps onto a second row instead, and if even that isn't
/// enough it drops its least important controls — every one of which also
/// lives in the panel the Tempo button opens, so nothing is ever only
/// reachable by scrolling.
library;

/// The gap [dockItemsThatFit] assumes between two controls, matching the
/// `Wrap` the dock lays them out with.
const dockItemSpacing = 12.0;

/// How many rows [widths] need at [available] width, laid out the way
/// `Wrap` does it: fill a row until the next item doesn't fit, then break.
int dockRowsNeeded(List<double> widths, double available, {double spacing = dockItemSpacing}) {
  if (widths.isEmpty) return 0;
  var rows = 1;
  var used = 0.0;
  for (final width in widths) {
    if (used == 0) {
      used = width;
      continue;
    }
    if (used + spacing + width <= available) {
      used += spacing + width;
    } else {
      rows++;
      used = width;
    }
  }
  return rows;
}

/// The indices of [widths] to actually show, in display order.
///
/// Items named in [dropOrder] are given up one at a time, in that order,
/// until what's left fits in [maxRows]. Anything not in [dropOrder] stays
/// whatever happens — the dock is where you reach for Stop and Blackout,
/// and they don't get to disappear because the screen is narrow.
List<int> dockItemsThatFit({
  required List<double> widths,
  required List<int> dropOrder,
  required double available,
  int maxRows = 2,
  double spacing = dockItemSpacing,
}) {
  final keep = [for (var i = 0; i < widths.length; i++) i];
  if (!available.isFinite || available <= 0) return keep;

  bool fits() =>
      dockRowsNeeded([for (final i in keep) widths[i]], available, spacing: spacing) <= maxRows;

  for (final candidate in dropOrder) {
    if (fits()) break;
    keep.remove(candidate);
  }
  // If it still doesn't fit, what's left is the set that can't be given up:
  // it wraps onto however many rows it needs rather than hiding a control.
  return keep;
}

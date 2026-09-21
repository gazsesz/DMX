import 'package:dmx_controller/core/widgets/dock_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The closed dock strip's layout rule. The widths here are the real ones:
/// a dock button is 62, the now-playing chip 96 idle / 150 playing, the
/// master fader 124, with 12 between each.
void main() {
  // chip, start/stop, beat, autofade, master, blackout, tempo
  const idle = <double>[96, 62, 62, 62, 124, 62, 62];
  const playing = <double>[150, 62, 62, 62, 124, 62, 62];
  // Auto fade goes before the master fader, even though the fader is wider:
  // the fader is a live control with no other shortcut, auto fade is a
  // switch you set once and it's in the panel too.
  const dropOrder = [3, 4];

  group('rows needed', () {
    test('everything on one row when there is room', () {
      expect(dockRowsNeeded(playing, 1004), 1);
    });

    test('a tablet stood upright needs two', () {
      // 600dp wide minus the strip's own padding.
      expect(dockRowsNeeded(playing, 580), 2);
    });

    test('a 360dp phone needs three', () {
      expect(dockRowsNeeded(playing, 340), 3);
    });

    test('nothing to lay out needs no rows', () {
      expect(dockRowsNeeded(const [], 340), 0);
    });
  });

  group('what fits', () {
    test('a landscape tablet keeps the lot', () {
      expect(
        dockItemsThatFit(widths: playing, dropOrder: dropOrder, available: 1004),
        [0, 1, 2, 3, 4, 5, 6],
      );
    });

    test('an upright tablet keeps the lot too, across two rows', () {
      final keep = dockItemsThatFit(widths: playing, dropOrder: dropOrder, available: 580);
      expect(keep, [0, 1, 2, 3, 4, 5, 6]);
      expect(dockRowsNeeded([for (final i in keep) playing[i]], 580), 2);
    });

    test('a phone gives up auto fade rather than taking a third row', () {
      final keep = dockItemsThatFit(widths: playing, dropOrder: dropOrder, available: 340);
      expect(keep, [0, 1, 2, 4, 5, 6]);
      expect(dockRowsNeeded([for (final i in keep) playing[i]], 340), 2);
    });

    test('Blackout and the panel button survive even a hopeless width', () {
      final keep = dockItemsThatFit(widths: idle, dropOrder: dropOrder, available: 120);
      // Everything droppable is gone, and what's left is what has to stay.
      expect(keep, [0, 1, 2, 5, 6]);
    });

    test('an unbounded width keeps everything rather than guessing', () {
      expect(
        dockItemsThatFit(widths: playing, dropOrder: dropOrder, available: double.infinity),
        [0, 1, 2, 3, 4, 5, 6],
      );
    });
  });
}

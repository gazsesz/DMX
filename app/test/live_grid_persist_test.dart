import 'dart:convert';

import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything set on the Grid / Mixer survives the project file.
void main() {
  test('lanes, Amounts, clips (moves centre, beam, shows) and row ids round-trip', () {
    var g = LiveGrid.starter();
    g = g
        .withLane(g.lane('level')!.copyWith(amount: 0.4, name: 'Dimmer'))
        .withLane(g.lane('show')!.copyWith(layerId: 'layer-2'))
        .withClip(
          'moves',
          0,
          const LiveClip(
            name: 'Pointed',
            moves: MovementFx(shape: MovementShape.circle, sizePanDeg: 20, sizeTiltDeg: 10, center: PanTilt(1000, 50000)),
          ),
        )
        .withClip('beam', 0, const LiveClip(name: 'Prism', beam: LiveBeamFx(gobo: 40, prism: 200, prismRotation: 0.5)))
        .withClip('show', 1, const LiveClip(name: 'Bank 1', show: LiveShowRef(kind: LiveShowKind.bank, id: 'b1')))
        .moveLane('beam', -2)
        .addRow('Mix 6')
        .duplicateRow(0, 'Intro copy');
    final text = jsonEncode(g.toJson());
    final back = LiveGrid.fromJson(jsonDecode(text) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), text);
    expect(back.lane('level')!.amount, 0.4);
    expect(back.lane('level')!.name, 'Dimmer');
    expect(back.clipAt('moves', 0)!.moves!.center, const PanTilt(1000, 50000));
    expect(back.clipAt('beam', 0)!.beam!.prism, 200);
    expect(back.rowIds, g.rowIds);
    expect([for (final l in back.lanes) l.id], [for (final l in g.lanes) l.id]);
  });
}

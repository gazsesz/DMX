import 'dart:math' as math;

import '../../models/fixture_mounting.dart';
import '../../models/pan_tilt.dart';

/// Turning a spot on the stage into a moving head's pan/tilt, and back.
///
/// Coordinates are the stage plan's, in metres: x runs stage left to right
/// as the audience sees it, y from upstage towards the audience, z up from
/// the floor. Directions on the plan are measured from +y (towards the
/// audience) round towards +x, matching [FixtureMounting.facingDeg].
///
/// The head model is the one nearly every mover shares: tilt at the middle
/// of its travel points the beam straight along the yoke — down for a hung
/// head, up for a standing one — and pan at the middle of its travel faces
/// [FixtureMounting.facingDeg]. Anything a particular fixture does
/// differently is what the invert flags and the calibration offsets are for.

/// Where one head hangs and how far it can turn.
class AimRig {
  final double x;
  final double y;
  final FixtureMounting mounting;
  final int panRangeDeg;
  final int tiltRangeDeg;

  const AimRig({
    required this.x,
    required this.y,
    required this.mounting,
    required this.panRangeDeg,
    required this.tiltRangeDeg,
  });

  double get z => mounting.heightM;
  bool get _hanging => mounting.mount == MountKind.hanging;

  /// A hung head is upside down, so seen from above its pan turns the other
  /// way round to a standing one.
  double get _panSign => (_hanging ? -1.0 : 1.0) * (mounting.invertPan ? -1.0 : 1.0);
  double get _tiltSign => mounting.invertTilt ? -1.0 : 1.0;
}

/// The answer to "aim at this spot": the position to send, and whether the
/// head can actually get there — a spot behind a head with only 180° of
/// tilt can't be reached, and the head is left at the nearest it can do.
class AimResult {
  final PanTilt position;
  final bool reachable;

  const AimResult(this.position, {required this.reachable});
}

double _deg(double radians) => radians * 180 / math.pi;
double _rad(double degrees) => degrees * math.pi / 180;

/// Pan/tilt in degrees from the centre of travel → the 16-bit position.
PanTilt degreesToPanTilt(double panDeg, double tiltDeg, {required int panRangeDeg, required int tiltRangeDeg}) {
  int scale(double deg, int range) => ((deg + range / 2) / range * PanTilt.max).round().clamp(0, PanTilt.max);
  return PanTilt(scale(panDeg, panRangeDeg), scale(tiltDeg, tiltRangeDeg));
}

/// The inverse of [degreesToPanTilt]: (pan, tilt) in degrees from centre.
(double, double) panTiltToDegrees(PanTilt position, {required int panRangeDeg, required int tiltRangeDeg}) {
  double degrees(int value, int range) => value / PanTilt.max * range - range / 2;
  return (degrees(position.pan, panRangeDeg), degrees(position.tilt, tiltRangeDeg));
}

/// Aims [rig] at the point ([tx], [ty], [tz]).
///
/// A 540° pan reaches most spots two or three different ways (and the same
/// spot again with pan half a turn round and tilt flipped). [previous] picks
/// between them: the answer closest to where the head already is, so moving
/// a target a little never sends a head spinning the long way round.
AimResult aimAt(AimRig rig, {required double tx, required double ty, double tz = 0, PanTilt? previous}) {
  final dx = tx - rig.x;
  final dy = ty - rig.y;
  final dz = tz - rig.z;
  final horizontal = math.sqrt(dx * dx + dy * dy);

  // Angle away from straight along the yoke: 0 = right under (or over) the
  // head, 90 = level with it.
  final theta = _deg(math.atan2(horizontal, rig._hanging ? -dz : dz));
  final (previousPan, previousTilt) = previous == null
      ? (0.0, 0.0)
      : panTiltToDegrees(previous, panRangeDeg: rig.panRangeDeg, tiltRangeDeg: rig.tiltRangeDeg);

  // Straight below the head every pan is right; keep the one it has.
  final double relative;
  if (horizontal < 1e-6) {
    relative = previousPan * rig._panSign;
  } else {
    relative = _deg(math.atan2(dx, dy)) - rig.mounting.facingDeg;
  }

  final halfPan = rig.panRangeDeg / 2;
  final halfTilt = rig.tiltRangeDeg / 2;
  (double, double)? best;
  var bestCost = double.infinity;
  (double, double)? nearest;
  var nearestOvershoot = double.infinity;

  for (final flipped in [false, true]) {
    final basePan = rig._panSign * (relative + (flipped ? 180 : 0));
    final tilt = (flipped ? -theta : theta) * rig._tiltSign + rig.mounting.tiltOffsetDeg;
    for (var turns = -2; turns <= 2; turns++) {
      final pan = _wrap180(basePan) + 360 * turns + rig.mounting.panOffsetDeg;
      final overshoot = math.max(0, pan.abs() - halfPan) + math.max(0, tilt.abs() - halfTilt);
      if (overshoot == 0) {
        final cost = (pan - previousPan).abs() + 0.5 * (tilt - previousTilt).abs();
        if (cost < bestCost) {
          bestCost = cost;
          best = (pan, tilt);
        }
      } else if (overshoot < nearestOvershoot) {
        nearestOvershoot = overshoot.toDouble();
        nearest = (pan.clamp(-halfPan, halfPan), tilt.clamp(-halfTilt, halfTilt));
      }
    }
  }

  final chosen = best ?? nearest!;
  return AimResult(
    degreesToPanTilt(chosen.$1, chosen.$2, panRangeDeg: rig.panRangeDeg, tiltRangeDeg: rig.tiltRangeDeg),
    reachable: best != null,
  );
}

/// Where [rig]'s beam at [position] meets the horizontal plane at height
/// [planeZ] — or null when it never does (pointing level, or away from it).
(double, double)? beamLandsAt(AimRig rig, PanTilt position, {double planeZ = 0}) {
  final (pan, tilt) = panTiltToDegrees(position, panRangeDeg: rig.panRangeDeg, tiltRangeDeg: rig.tiltRangeDeg);
  var relative = (pan - rig.mounting.panOffsetDeg) * rig._panSign;
  var theta = (tilt - rig.mounting.tiltOffsetDeg) * rig._tiltSign;
  if (theta < 0) {
    theta = -theta;
    relative += 180;
  }
  if (theta >= 89.5) return null;
  final drop = rig._hanging ? rig.z - planeZ : planeZ - rig.z;
  if (drop <= 0) return null;
  final distance = drop * math.tan(_rad(theta));
  final azimuth = _rad(rig.mounting.facingDeg + relative);
  return (rig.x + distance * math.sin(azimuth), rig.y + distance * math.cos(azimuth));
}

double _wrap180(double degrees) {
  final wrapped = (degrees + 180) % 360;
  return (wrapped < 0 ? wrapped + 360 : wrapped) - 180;
}

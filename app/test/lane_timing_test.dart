import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/models/chase.dart';

void main() {
  test('lane timings survive a JSON round trip, unlisted lanes follow the dock', () {
    final chase = Chase(
      id: 'c',
      name: 'Sweep + beat',
      steps: const [ChaseStep(sceneId: 'a')],
      laneTimings: const {'layer-2': LaneTiming.free, 'layer-1': LaneTiming.onBeat},
    );
    final back = Chase.fromJson(chase.toJson());
    expect(back.timingOfLane('layer-2'), LaneTiming.free);
    expect(back.timingOfLane('layer-1'), LaneTiming.onBeat);
    expect(back.timingOfLane('layer-9'), LaneTiming.followApp);
  });

  test('an old save without lane timings loads as follow-the-dock', () {
    final back = Chase.fromJson({'id': 'c', 'name': 'old', 'steps': <dynamic>[]});
    expect(back.laneTimings, isEmpty);
  });
}

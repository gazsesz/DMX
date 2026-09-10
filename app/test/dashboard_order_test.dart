import 'package:dmx_controller/models/dashboard_trigger.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/dashboard_providers.dart';
import 'package:dmx_controller/state/smart_program_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dragging a Dashboard tile onto another calls `move`, and the index
/// shifting differs depending on which direction you drag.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container.read(dashboardTriggersProvider.notifier).loadAll(const [
      DashboardTriggerRef(id: 'a', kind: TriggerKind.bank),
      DashboardTriggerRef(id: 'b', kind: TriggerKind.chase),
      DashboardTriggerRef(id: 'c', kind: TriggerKind.bank),
    ]);
    container.read(smartProgramsProvider.notifier).loadAll(const [
      SmartProgram(id: 'p1', name: 'One'),
      SmartProgram(id: 'p2', name: 'Two'),
      SmartProgram(id: 'p3', name: 'Three'),
    ]);
  });

  tearDown(() => container.dispose());

  List<String> triggerIds() => [for (final t in container.read(dashboardTriggersProvider)) t.id];
  List<String> programIds() => [for (final p in container.read(smartProgramsProvider)) p.id];

  test('quick trigger dragged later lands where the target was', () {
    container.read(dashboardTriggersProvider.notifier).move(0, 2);
    expect(triggerIds(), ['b', 'c', 'a']);
  });

  test('quick trigger dragged earlier lands where the target was', () {
    container.read(dashboardTriggersProvider.notifier).move(2, 0);
    expect(triggerIds(), ['c', 'a', 'b']);
  });

  test('smart programs reorder the same way', () {
    container.read(smartProgramsProvider.notifier).move(1, 2);
    expect(programIds(), ['p1', 'p3', 'p2']);
  });

  test('a no-op or out-of-range move changes nothing', () {
    container.read(dashboardTriggersProvider.notifier).move(1, 1);
    container.read(dashboardTriggersProvider.notifier).move(0, 9);
    container.read(smartProgramsProvider.notifier).move(-1, 1);
    expect(triggerIds(), ['a', 'b', 'c']);
    expect(programIds(), ['p1', 'p2', 'p3']);
  });
}

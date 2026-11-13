import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/fixtures/fixture_layout_screen.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final par = FixtureProfile(
    id: 'par',
    name: 'PAR',
    category: FixtureCategory.rgb,
    channels: const [FixtureChannel(offset: 0, function: ChannelFunction.red)],
  );

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(patchedFixturesProvider.notifier).loadAll([
      PatchedFixture(id: 'p1', label: 'PAR 1', profile: par, universeId: 'u1', startChannel: 0, layoutX: 0.3, layoutY: 0.5),
    ]);
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const FixtureLayoutScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Width of the stage canvas the lamp sits on.
  double canvasWidth(WidgetTester tester) =>
      tester.getSize(find.ancestor(of: find.text('PAR 1'), matching: find.byType(Stack)).last).width;

  testWidgets('a lamp follows the finger one to one, small steps included', (tester) async {
    final container = await open(tester);
    final width = canvasWidth(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('PAR 1')));
    // Many small moves, several per frame — the way a finger reports them.
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(5, 0));
      if (i.isEven) await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    final x = container.read(patchedFixturesProvider).single.layoutX;
    expect(x, closeTo(0.3 + 200 / width, 0.005));
  });

  testWidgets('the patch is written once, when the finger lifts', (tester) async {
    final container = await open(tester);
    var writes = 0;
    container.listen(patchedFixturesProvider, (_, _) => writes++);
    final gesture = await tester.startGesture(tester.getCenter(find.text('PAR 1')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(10, 4));
      await tester.pump();
    }
    expect(writes, 0);
    await gesture.up();
    await tester.pump();
    expect(writes, 1);
  });
}

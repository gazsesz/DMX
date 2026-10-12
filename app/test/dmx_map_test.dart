import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/settings/dmx_map_screen.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FixtureProfile _profile(String name, int channels) => FixtureProfile(
  id: name,
  name: name,
  category: FixtureCategory.generic,
  channels: [for (var i = 0; i < channels; i++) FixtureChannel(offset: i, function: ChannelFunction.generic)],
);

PatchedFixture _fixture(String id, int channels, int start, {String universe = 'u1'}) =>
    PatchedFixture(id: id, label: id, profile: _profile('P$channels', channels), universeId: universe, startChannel: start);

void main() {
  group('layout', () {
    test('a fixture is one segment per row, and only its first segment carries the name', () {
      final a = _fixture('A', 40, 20); // channels 21-60: row 0 (21-32), row 1 (33-60)
      final layout = DmxMapLayout.of([a], [a]);
      final row0 = layout.rows[0].where((s) => s.fixture != null).toList();
      final row1 = layout.rows[1].where((s) => s.fixture != null).toList();
      expect(row0.single.start, 20);
      expect(row0.single.end, 31);
      expect(row0.single.isHead, isTrue);
      expect(row1.single.start, 32);
      expect(row1.single.end, 59);
      expect(row1.single.isHead, isFalse);
      expect(layout.used, 40);
      expect(layout.firstFree, 1);
    });

    test('free channels are cells of their own', () {
      final layout = DmxMapLayout.of(const [], const []);
      expect(layout.rows.length, 16);
      expect(layout.rows.every((r) => r.length == 32), isTrue);
      expect(layout.used, 0);
    });

    test('overlapping fixtures are flagged', () {
      final a = _fixture('A', 10, 0);
      final b = _fixture('B', 10, 5);
      final layout = DmxMapLayout.of([a, b], [a, b]);
      expect(layout.conflicts, 5);
      expect(layout.rows[0].any((s) => s.conflict), isTrue);
    });

    test('first free skips the patched block; a full universe has none', () {
      final a = _fixture('A', 5, 0);
      expect(DmxMapLayout.of([a], [a]).firstFree, 6);
      final full = _fixture('F', 512, 0);
      expect(DmxMapLayout.of([full], [full]).firstFree, isNull);
    });

    test('a fixture running past channel 512 is cut off, not a crash', () {
      final a = _fixture('A', 20, 500);
      final layout = DmxMapLayout.of([a], [a]);
      expect(layout.used, 12);
    });
  });

  testWidgets('the map shows fixtures per universe and opens a fixture\'s channels', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(universesProvider.notifier).loadAll(const [
      UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0),
      UniverseConfig(id: 'u2', name: 'Universe 2', universe: 1),
    ]);
    container.read(patchedFixturesProvider.notifier).loadAll([
      _fixture('Robo', 12, 0),
      _fixture('Wash', 8, 100, universe: 'u2'),
    ]);
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const DmxMapScreen()),
    ));
    await tester.pump();
    expect(find.text('Robo'), findsOneWidget);
    expect(find.text('Wash'), findsNothing);

    await tester.tap(find.text('Robo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('channels 1–12'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.text('Universe 2'));
    await tester.pumpAndSettle();
    expect(find.text('Wash'), findsOneWidget);
    expect(find.text('Robo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

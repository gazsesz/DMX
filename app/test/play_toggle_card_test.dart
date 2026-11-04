import 'package:dmx_controller/core/theme/app_colors.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/play_toggle_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the whole left column toggles, the rest of the card opens the editor', (tester) async {
    var toggles = 0;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              PlayToggleCard(
                active: false,
                icon: Icons.fast_forward_outlined,
                accent: AppColors.accent,
                accentOn: AppColors.accentOn,
                toggleKey: const ValueKey('toggle'),
                onToggle: () => toggles++,
                onOpen: () => opens++,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('My chase'), Text('8 steps · 0.50s/step')],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final zone = tester.getRect(find.byKey(const ValueKey('toggle')));
    expect(zone.width, PlayToggleCard.toggleWidth);
    expect(zone.height, greaterThanOrEqualTo(72));

    // Corners of the column, well off the round button itself.
    await tester.tapAt(zone.topLeft + const Offset(4, 4));
    await tester.tapAt(zone.bottomRight - const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 500));
    expect(toggles, 2);
    expect(opens, 0);

    await tester.tap(find.text('My chase'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opens, 1);
    expect(toggles, 2);
  });

  testWidgets('running shows Stop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayToggleCard(
            active: true,
            icon: Icons.auto_graph,
            accent: AppColors.accent2,
            accentOn: AppColors.accent2On,
            onToggle: () {},
            onOpen: () {},
            child: const Text('Program'),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.auto_graph), findsNothing);
  });
}

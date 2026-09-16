import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/core/widgets/color_picker_dialog.dart';
import 'package:dmx_controller/state/color_palette_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The scene editor's colour picker: named presets, a palette to mix
/// anything else, and the colours you keep showing up alongside the
/// presets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpPicker(
    WidgetTester tester, {
    List<int> initial = const [255, 0, 0],
    ValueChanged<List<int>>? onPreview,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ColorPickerDialog(initial: initial, onPreview: onPreview),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('opens on the swatches and switches to the palette', (tester) async {
    await pumpPicker(tester);
    expect(find.text('PRESETS'), findsOneWidget);
    expect(find.text('MY COLOURS'), findsOneWidget);

    await tester.tap(find.text('Palette'));
    await tester.pump();

    expect(find.text('HUE'), findsOneWidget);
    expect(find.text('#FF0000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mixed colour is saved and then sits among the swatches', (tester) async {
    final container = await pumpPicker(tester, initial: const [0, 0, 255]);
    await tester.tap(find.text('Palette'));
    await tester.pump();

    await tester.tap(find.text('Save colour'));
    await tester.pump();

    expect(container.read(customColorsProvider), [
      [0, 0, 255],
    ]);
    // Saved twice is still one colour, and the button says so.
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.text('Swatches'));
    await tester.pump();
    expect(find.text('Mix one on the Palette tab and save it — it shows up here, in every project.'), findsNothing);
  });

  testWidgets('dragging a slider previews live rather than waiting for the dialog to close', (tester) async {
    final seen = <List<int>>[];
    await pumpPicker(tester, onPreview: seen.add);
    await tester.tap(find.text('Palette'));
    await tester.pump();

    // The brightness track — last of the three.
    await tester.drag(find.byType(Slider).last, const Offset(-120, 0));
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(seen.last[0], lessThan(255));
  });
}

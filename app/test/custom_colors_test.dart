import 'package:dmx_controller/state/color_palette_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Colours you mix yourself are kept as hex strings in shared preferences,
/// so the round trip has to survive anything already stored — including a
/// file hand-edited with `#` prefixes or junk in it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The notifier reads and writes shared preferences by itself; without a
    // store behind it that's a missing plugin, not a failing assertion.
    SharedPreferences.setMockInitialValues({});
  });

  test('a colour survives the round trip', () {
    final restored = customColorsFromStrings([hexOf(const [255, 160, 20])]);
    expect(restored, [
      [255, 160, 20],
    ]);
  });

  test('hex is padded, so a dark colour is not six characters short', () {
    expect(hexOf(const [0, 8, 16]), '000810');
  });

  test('a stored entry that is not a colour is skipped rather than thrown on', () {
    final restored = customColorsFromStrings(['#22d3ee', 'nonsense', '', 'ff00']);
    expect(restored, [
      [34, 211, 238],
    ]);
  });

  test('the same colour is only saved once', () {
    final notifier = CustomColorsNotifier(const []);
    notifier.add([10, 20, 30]);
    notifier.add([10, 20, 30]);
    expect(notifier.state.length, 1);

    notifier.remove([10, 20, 30]);
    expect(notifier.state, isEmpty);
  });
}

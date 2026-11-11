import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prefAppLanguage = 'app.language';

/// The UI language the user picked on the Setup screen. [system] follows the
/// device language (Hungarian → Hungarian, anything else → English).
enum AppLanguage {
  system,
  en,
  hu;

  static AppLanguage fromName(String? name) =>
      AppLanguage.values.firstWhere((l) => l.name == name, orElse: () => AppLanguage.system);
}

/// Languages the app ships. English is the template and the fallback.
const supportedAppLocales = [Locale('en'), Locale('hu')];

/// The locale to hand to `MaterialApp.locale`. `null` for [AppLanguage.system]
/// lets Flutter resolve the device language through [resolveAppLocale].
Locale? localeFor(AppLanguage language) => switch (language) {
  AppLanguage.system => null,
  AppLanguage.en => const Locale('en'),
  AppLanguage.hu => const Locale('hu'),
};

/// Device locale → app locale: Hungarian stays Hungarian, everything else
/// falls back to English.
Locale resolveAppLocale(Iterable<Locale>? deviceLocales) {
  for (final l in deviceLocales ?? const <Locale>[]) {
    if (l.languageCode == 'hu') return const Locale('hu');
    if (l.languageCode == 'en') return const Locale('en');
  }
  return const Locale('en');
}

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier(super.initial);

  void set(AppLanguage next) {
    if (next == state) return;
    state = next;
    _persist(next);
  }

  Future<void> _persist(AppLanguage value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(prefAppLanguage, value.name);
  }
}

/// Loaded in `main()` before the first frame (overridden there), so the app
/// never flashes in the wrong language on start-up.
final appLanguageProvider = StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier(AppLanguage.system);
});

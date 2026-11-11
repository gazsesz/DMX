import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'l10n/generated/app_localizations.dart';
import 'state/locale_providers.dart';

class DmxControllerApp extends ConsumerWidget {
  /// The first screen. Only tests pass anything else (the splash screen
  /// loads the project and connects to the node, which a test can't finish).
  final Widget home;

  const DmxControllerApp({super.key, this.home = const SplashScreen()});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    return MaterialApp(
      title: 'SmART DMX Controller',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      locale: localeFor(language),
      supportedLocales: supportedAppLocales,
      localeListResolutionCallback: (deviceLocales, _) => resolveAppLocale(deviceLocales),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }
}

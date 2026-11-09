import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

final _englishFallback = lookupAppLocalizations(const Locale('en'));

/// `context.l10n.someKey` — shorthand for `AppLocalizations.of(context)`.
///
/// Falls back to English where no localizations delegate is installed
/// (widget tests that pump a bare `MaterialApp`), so a screen never crashes
/// just because it was built outside the real app.
extension L10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _englishFallback;
}

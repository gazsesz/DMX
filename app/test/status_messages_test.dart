import 'package:dmx_controller/l10n/generated/app_localizations.dart';
import 'package:dmx_controller/l10n/status_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final hu = lookupAppLocalizations(const Locale('hu'));

  test('English messages pass through unchanged in English', () {
    for (final m in [
      'Started Club 1',
      'Stopped Club 1',
      'Not connected — check Settings',
      'Beat sync already on',
      'Dropout off',
      'Imported 2 banks, 1 chase, 5 scenes',
      'Nothing called "Front"',
    ]) {
      expect(localizeStatus(m, en), m);
    }
  });

  test('known messages are translated to Hungarian', () {
    expect(localizeStatus('Started Club 1', hu), 'Elindítva: Club 1');
    expect(localizeStatus('Beat sync already on', hu), 'A Beat Sync már be van kapcsolva');
    expect(localizeStatus('Predict off', hu), 'Predict ki');
    expect(localizeStatus('Imported 2 banks, 1 chase, 5 scenes', hu), 'Importálva: 2 bank, 1 chase, 5 scene');
    expect(localizeStatus('"Wash" has no filled slots to play', hu), 'A(z) „Wash” bankban nincs kitöltött slot');
  });

  test('unknown messages are shown as they are', () {
    expect(localizeStatus('Something unexpected', hu), 'Something unexpected');
  });
}

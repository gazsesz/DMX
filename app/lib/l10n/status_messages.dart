import 'generated/app_localizations.dart';

/// Translates the status and error messages the playback, trigger and audio
/// code returns as plain English strings.
///
/// Those strings are also the remote-control API's answers (a watch macro
/// reads them), so they stay English at the source; the UI passes them
/// through here before showing them. Anything not recognised is shown as it
/// is.
String localizeStatus(String message, AppLocalizations l) {
  for (final (pattern, build) in _rules) {
    final m = pattern.firstMatch(message);
    if (m != null) return build(m, l);
  }
  return message;
}

String? localizeStatusOrNull(String? message, AppLocalizations l) =>
    message == null ? null : localizeStatus(message, l);

bool _on(String word) => word == 'on';

final List<(RegExp, String Function(RegExpMatch m, AppLocalizations l))> _rules = [
  (RegExp(r'^Started (.+)$'), (m, l) => l.statusStarted(m[1]!)),
  (RegExp(r'^Stopped (.+)$'), (m, l) => l.statusStopped(m[1]!)),
  (RegExp(r'^Not connected — check Settings$'), (m, l) => l.statusNotConnected),
  (RegExp(r'^(That )?[Bb]ank no longer exists$'), (m, l) => l.statusBankGone),
  (RegExp(r'^(That )?[Cc]hase no longer exists$'), (m, l) => l.statusChaseGone),
  (RegExp(r'^(That )?[Ss]mart program no longer exists$'), (m, l) => l.statusSmartGone),
  (RegExp(r'^Nothing has played( on this layer)? yet$'), (m, l) => l.statusNothingPlayed),
  (RegExp(r'^Beat sync (already )?(on|off)$'), (m, l) => l.statusBeatSync(m[1] != null ? 'already' : 'now', _on(m[2]!) ? 'on' : 'off')),
  (RegExp(r'^Predict (already )?(on|off)$'), (m, l) => l.statusPredict(m[1] != null ? 'already' : 'now', _on(m[2]!) ? 'on' : 'off')),
  (RegExp(r'^Dropout (already )?(on|off)$'), (m, l) => l.statusDropout(m[1] != null ? 'already' : 'now', _on(m[2]!) ? 'on' : 'off')),
  (RegExp(r'^No name given$'), (m, l) => l.statusNoName),
  (RegExp(r'^Nothing called "(.+)"$'), (m, l) => l.statusNothingCalled(m[1]!)),
  (RegExp(r'^Could not open the microphone for tempo tracking$'), (m, l) => l.statusMicTempo),
  (RegExp(r'^(.+) has no valid steps to play$'), (m, l) => l.statusNoValidSteps(m[1]!)),
  (RegExp(r'^"(.+)" has no filled slots to play$'), (m, l) => l.statusNoFilledSlots(m[1]!)),
  (RegExp(r'^"(.+)" has nothing to play$'), (m, l) => l.statusNothingToPlay(m[1]!)),
  (RegExp(r'^Add some cues to (.+) first$'), (m, l) => l.statusAddCues(m[1]!)),
  (RegExp(r'^Could not play (.+?): (.+)$'), (m, l) => l.statusCouldNotPlay(m[1]!, m[2]!)),
  (RegExp(r'^Microphone permission denied$'), (m, l) => l.statusMicDenied),
  (RegExp(r'^No microphone/input device found$'), (m, l) => l.statusNoMic),
  (RegExp(r'^Could not start the beat source$'), (m, l) => l.statusBeatSourceFailed),
  (RegExp(r'^No MIDI device selected — pick one in Setup$'), (m, l) => l.statusNoMidiSelected),
  (RegExp(r'^No MIDI input on this platform$'), (m, l) => l.statusNoMidiPlatform),
  (RegExp(r'^Socket not open$'), (m, l) => l.statusSocketNotOpen),
  (RegExp(r'^No ArtPollReply received from (.+)$'), (m, l) => l.statusNoArtPollReply(m[1]!)),
  (RegExp(r'^Could not open the socket: (.+)$'), (m, l) => l.statusSocketFailed(m[1]!)),
  (RegExp(r'^Imported (\d+ .+)$'), (m, l) => l.statusImported(_importParts(m[1]!, l))),
];

/// "2 banks, 1 chase, 5 scenes" → the same counts in the UI language.
String _importParts(String english, AppLocalizations l) => english
    .split(', ')
    .map((part) {
      final m = RegExp(r'^(\d+) (bank|chase|scene)s?$').firstMatch(part);
      if (m == null) return part;
      final n = int.parse(m[1]!);
      return switch (m[2]) {
        'bank' => l.statusCountBanks(n),
        'chase' => l.statusCountChases(n),
        _ => l.statusCountScenes(n),
      };
    })
    .join(', ');

/// Whatever a chase, bank, Smart Program or the dock listens to for its
/// beat clock — a microphone onset detector or a MIDI clock, used
/// interchangeably by everything downstream.
///
/// Every consumer only ever needs these five members. Anything
/// source-specific (the microphone's sensitivity/band sliders and VU meter,
/// a MIDI source's device list) stays on the concrete implementation and is
/// only ever touched where that source is known to be the active one — see
/// `activeBeatSourceProvider`.
abstract class BeatSource {
  Stream<DateTime> get beatEvents;
  bool get isListening;
  String? get lastError;

  /// Starts listening. Returns false if it couldn't — check [lastError] for
  /// why.
  Future<bool> start();
  Future<void> stop();
}

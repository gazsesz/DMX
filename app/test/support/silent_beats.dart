import 'package:dmx_controller/core/audio/beat_source.dart';

/// A beat source that never beats and never touches a microphone, for tests
/// that stop or start layers (which reach for the active beat source).
class SilentBeats implements BeatSource {
  @override
  Stream<DateTime> get beatEvents => const Stream.empty();
  @override
  bool get isListening => false;
  @override
  String? get lastError => null;
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
}

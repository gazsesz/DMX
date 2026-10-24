// Phase-0 spike for the Song Show plan (SONG_SHOW_PLAN.html): can we decode,
// play and draw a waveform for mp3/wav/flac/m4a on the target devices, and how
// stable is the playback clock? Not part of the app; run with
//   flutter run -d windows -t lib/spike_song_main.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

void main() => runApp(const MaterialApp(home: SpikeScreen(), debugShowCheckedModeBanner: false));

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _log = <String>[];
  AudioSource? _source;
  SoundHandle? _handle;
  Duration _length = Duration.zero;
  Float32List _wave = Float32List(0);
  Timer? _ticker;
  Duration _pos = Duration.zero;

  // Clock stability: compare getPosition deltas against the wall clock.
  final _wall = Stopwatch();
  Duration _posAtWallStart = Duration.zero;
  double _maxDriftMs = 0;
  int _staleTicks = 0;
  Duration _lastPos = Duration.zero;
  double _minDriftMs = 0;
  double _driftSignedMs = 0;
  // Position update steps and how well wall-clock interpolation predicts them.
  Duration _lastChangeWall = Duration.zero;
  final _steps = <double>[];
  final _interpErr = <double>[];

  void _resetStats() {
    _maxDriftMs = 0;
    _minDriftMs = 0;
    _staleTicks = 0;
    _steps.clear();
    _interpErr.clear();
    _lastChangeWall = _wall.elapsed;
  }

  String _report(String label) {
    String pct(List<double> v, double q) {
      if (v.isEmpty) return '-';
      final c = [...v]..sort();
      return c[((c.length - 1) * q).round()].toStringAsFixed(1);
    }

    final e = _interpErr.map((x) => x.abs()).toList();
    return '$label: drift min ${_minDriftMs.toStringAsFixed(1)} / max ${_maxDriftMs.toStringAsFixed(1)} / '
        'last ${_driftSignedMs.toStringAsFixed(1)} ms; position steps p50 ${pct(_steps, .5)} p95 ${pct(_steps, .95)} '
        'max ${pct(_steps, 1)} ms (n=${_steps.length}); interp error p50 ${pct(e, .5)} p95 ${pct(e, .95)} '
        'max ${pct(e, 1)} ms; stale ticks $_staleTicks';
  }

  void _say(String s) {
    debugPrint('SPIKE $s');
    if (mounted) setState(() => _log.insert(0, s));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final sw = Stopwatch()..start();
    await SoLoud.instance.init();
    _say('SoLoud init ${sw.elapsedMilliseconds} ms');
    const auto = String.fromEnvironment('SPIKE_FILE');
    if (auto.isNotEmpty) {
      await _load(auto);
      await _play();
      await Future<void>.delayed(const Duration(seconds: 20));
      _say(_report('PRE-SEEK 20 s'));
      _seek(_length * 0.5);
      await Future<void>.delayed(const Duration(seconds: 10));
      _say(_report('POST-SEEK 10 s'));
      _say('AUTO DONE');
    }
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(type: FileType.audio);
    final path = res.firstOrNull?.path;
    if (path != null) await _load(path);
  }

  Future<void> _load(String path) async {
    await _stop();
    final name = path.split(RegExp(r'[\\/]')).last;
    final sw = Stopwatch()..start();
    try {
      _source = await SoLoud.instance.loadFile(path, mode: LoadMode.disk);
    } catch (e) {
      _say('LOAD FAILED $name: $e');
      return;
    }
    _length = SoLoud.instance.getLength(_source!);
    _say('$name: loadFile(disk) ${sw.elapsedMilliseconds} ms, length ${_length.inMilliseconds / 1000}s');

    sw.reset();
    final bins = await SoLoud.instance.readSamplesFromFile(path, 1000, average: true);
    _say('waveform 1000 bins: ${sw.elapsedMilliseconds} ms');
    setState(() => _wave = bins);

    // What an offline analysis would need: ~11 kHz of mono samples.
    final analysisSamples = (_length.inMilliseconds / 1000 * 11025).round();
    sw.reset();
    final pcm = await SoLoud.instance.readSamplesFromFile(path, analysisSamples, average: true);
    var peak = 0.0;
    for (final v in pcm) {
      peak = max(peak, v.abs());
    }
    _say('analysis PCM $analysisSamples samples (${(pcm.lengthInBytes / 1048576).toStringAsFixed(1)} MB): '
        '${sw.elapsedMilliseconds} ms, peak ${peak.toStringAsFixed(2)}');
  }

  Future<void> _play() async {
    final s = _source;
    if (s == null) return;
    await _stop(keepSource: true);
    _handle = SoLoud.instance.play(s);
    _wall
      ..reset()
      ..start();
    _posAtWallStart = SoLoud.instance.getPosition(_handle!);
    _resetStats();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final h = _handle;
      if (h == null) return;
      final p = SoLoud.instance.getPosition(h);
      final now = _wall.elapsed;
      final drift = ((p - _posAtWallStart) - now).inMicroseconds / 1000;
      _driftSignedMs = drift;
      if (drift > _maxDriftMs) _maxDriftMs = drift;
      if (drift < _minDriftMs) _minDriftMs = drift;
      if (p == _lastPos) {
        _staleTicks++;
      } else {
        _steps.add((now - _lastChangeWall).inMicroseconds / 1000);
        // What interpolating from the previous value would have predicted.
        final predicted = _lastPos + (now - _lastChangeWall);
        _interpErr.add((predicted - p).inMicroseconds / 1000);
        _lastChangeWall = now;
      }
      _lastPos = p;
      setState(() => _pos = p);
    });
  }

  void _seek(Duration to) {
    final h = _handle;
    if (h == null) return;
    final sw = Stopwatch()..start();
    SoLoud.instance.seek(h, to);
    _say('seek to ${to.inSeconds}s: ${sw.elapsedMicroseconds} us, position now '
        '${SoLoud.instance.getPosition(h).inMilliseconds} ms');
    _wall
      ..reset()
      ..start();
    _posAtWallStart = SoLoud.instance.getPosition(h);
    _lastPos = _posAtWallStart;
    _resetStats();
  }

  Future<void> _stop({bool keepSource = false}) async {
    _ticker?.cancel();
    final h = _handle;
    _handle = null;
    if (h != null) SoLoud.instance.stop(h);
    if (!keepSource) {
      final s = _source;
      _source = null;
      if (s != null) await SoLoud.instance.disposeSource(s);
    }
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frac = _length.inMilliseconds == 0 ? 0.0 : _pos.inMilliseconds / _length.inMilliseconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Song Show spike')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _pick, child: const Text('Pick file')),
            FilledButton(onPressed: _play, child: const Text('Play')),
            OutlinedButton(onPressed: _stop, child: const Text('Stop')),
            OutlinedButton(onPressed: () => _seek(_length * 0.5), child: const Text('Seek 50%')),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(painter: _WavePainter(_wave, frac)),
          ),
          Text('pos ${_pos.inMilliseconds} ms · max drift ${_maxDriftMs.toStringAsFixed(1)} ms · '
              'stale ticks $_staleTicks'),
          const Divider(),
          Expanded(child: ListView(children: [for (final l in _log) Text(l)])),
        ]),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.wave, this.frac);
  final Float32List wave;
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyan;
    final mid = size.height / 2;
    for (var i = 0; i < wave.length; i++) {
      final x = i / wave.length * size.width;
      final h = wave[i].abs().clamp(0.0, 1.0) * mid * 2;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
    }
    canvas.drawRect(Rect.fromLTWH(frac * size.width, 0, 2, size.height), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

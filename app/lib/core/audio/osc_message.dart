import 'dart:convert';
import 'dart:typed_data';

/// One decoded Open Sound Control message: an address like
/// `/master/beat/trigger/1` and its arguments, already converted to Dart
/// values (double for `f`/`d`, int for `i`/`h`, String for `s`, bool for
/// `T`/`F`, null for `N`).
class OscMessage {
  final String address;
  final List<Object?> args;

  const OscMessage(this.address, this.args);

  /// The first argument as a number, or null if there isn't a numeric one.
  double? get firstNumber {
    if (args.isEmpty) return null;
    final value = args.first;
    if (value is num) return value.toDouble();
    if (value is bool) return value ? 1 : 0;
    return null;
  }

  @override
  String toString() => 'OscMessage($address, $args)';
}

/// Decodes one UDP datagram of OSC 1.0 — a single message or a `#bundle`
/// (nested bundles included) — into its messages, in order.
///
/// Pure byte parsing with no socket involved, so it's unit-testable against
/// hand-built packets. Malformed input never throws: whatever decoded
/// cleanly before the damage is returned and the rest is dropped, since a
/// beat source would rather miss one packet than stop listening.
List<OscMessage> decodeOscPacket(Uint8List bytes) {
  final out = <OscMessage>[];
  try {
    _decodeElement(ByteData.sublistView(bytes), out);
  } on _OscFormatError {
    // Keep what decoded before the bad part.
  }
  return out;
}

void _decodeElement(ByteData data, List<OscMessage> out) {
  if (data.lengthInBytes == 0) return;
  final reader = _Reader(data);
  final head = reader.string();
  if (head == '#bundle') {
    reader.skip(8); // time tag — this is live data, everything is "now"
    while (!reader.atEnd) {
      final size = reader.int32();
      if (size < 0 || size % 4 != 0) throw const _OscFormatError();
      _decodeElement(reader.view(size), out);
    }
    return;
  }
  if (!head.startsWith('/')) throw const _OscFormatError();
  final args = <Object?>[];
  if (!reader.atEnd) {
    final tags = reader.string();
    if (!tags.startsWith(',')) throw const _OscFormatError();
    for (final tag in tags.codeUnits.skip(1)) {
      switch (String.fromCharCode(tag)) {
        case 'f':
          args.add(reader.float32());
        case 'd':
          args.add(reader.float64());
        case 'i':
          args.add(reader.int32());
        case 'h':
          args.add(reader.int64());
        case 's':
        case 'S':
          args.add(reader.string());
        case 'T':
          args.add(true);
        case 'F':
          args.add(false);
        case 'N':
        case 'I':
          args.add(null);
        default:
          // An argument type this doesn't know the size of — nothing after
          // it can be located, so stop here with what's been read.
          out.add(OscMessage(head, args));
          return;
      }
    }
  }
  out.add(OscMessage(head, args));
}

class _OscFormatError implements Exception {
  const _OscFormatError();
}

class _Reader {
  final ByteData _data;
  int _pos = 0;

  _Reader(this._data);

  bool get atEnd => _pos >= _data.lengthInBytes;

  void _need(int n) {
    if (n < 0 || _pos + n > _data.lengthInBytes) throw const _OscFormatError();
  }

  void skip(int n) {
    _need(n);
    _pos += n;
  }

  ByteData view(int n) {
    _need(n);
    final view = ByteData.sublistView(_data, _pos, _pos + n);
    _pos += n;
    return view;
  }

  int int32() {
    _need(4);
    final v = _data.getInt32(_pos);
    _pos += 4;
    return v;
  }

  int int64() {
    _need(8);
    final v = _data.getInt64(_pos);
    _pos += 8;
    return v;
  }

  double float32() {
    _need(4);
    final v = _data.getFloat32(_pos);
    _pos += 4;
    return v;
  }

  double float64() {
    _need(8);
    final v = _data.getFloat64(_pos);
    _pos += 8;
    return v;
  }

  /// A null-terminated string padded to a multiple of 4 bytes.
  String string() {
    final start = _pos;
    var end = start;
    while (end < _data.lengthInBytes && _data.getUint8(end) != 0) {
      end++;
    }
    if (end >= _data.lengthInBytes) throw const _OscFormatError();
    final text = utf8.decode(
      Uint8List.sublistView(_data, start, end),
      allowMalformed: true,
    );
    final padded = (end - start + 1 + 3) & ~3;
    skip(padded);
    return text;
  }
}

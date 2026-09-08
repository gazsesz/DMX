import 'dart:typed_data';

const _artNetId = 'Art-Net';
const _opDmx = 0x5000;
const _opPoll = 0x2000;
const _opPollReply = 0x2100;
const _protocolVersion = 14;

/// Builds an Art-Net ArtDmx packet carrying up to 512 DMX channel values for
/// one Net/Sub-Net/Universe address (Art-Net 4 15-bit Port-Address scheme).
Uint8List buildArtDmxPacket({
  required int net,
  required int subNet,
  required int universe,
  required int sequence,
  required Uint8List dmxData,
}) {
  assert(net >= 0 && net <= 127, 'Net must be 0-127');
  assert(subNet >= 0 && subNet <= 15, 'Sub-Net must be 0-15');
  assert(universe >= 0 && universe <= 15, 'Universe must be 0-15');
  assert(dmxData.length <= 512, 'DMX data cannot exceed 512 channels');

  // Art-Net requires an even, non-zero data length.
  final length = dmxData.isEmpty
      ? 2
      : (dmxData.length.isOdd ? dmxData.length + 1 : dmxData.length);
  final payload = Uint8List(length)..setRange(0, dmxData.length, dmxData);

  final builder = BytesBuilder()
    ..add(_artNetId.codeUnits)
    ..addByte(0)
    ..addByte(_opDmx & 0xFF)
    ..addByte((_opDmx >> 8) & 0xFF)
    ..addByte(0)
    ..addByte(_protocolVersion)
    ..addByte(sequence & 0xFF)
    ..addByte(0)
    ..addByte(((subNet & 0x0F) << 4) | (universe & 0x0F))
    ..addByte(net & 0x7F)
    ..addByte((length >> 8) & 0xFF)
    ..addByte(length & 0xFF)
    ..add(payload);

  return builder.toBytes();
}

/// Minimal 14-byte ArtPoll packet used to discover/ping an Art-Net node.
Uint8List buildArtPollPacket() {
  final builder = BytesBuilder()
    ..add(_artNetId.codeUnits)
    ..addByte(0)
    ..addByte(_opPoll & 0xFF)
    ..addByte((_opPoll >> 8) & 0xFF)
    ..addByte(0)
    ..addByte(_protocolVersion)
    ..addByte(0x00) // TalkToMe: no diagnostics, reply-on-change off
    ..addByte(0); // Priority
  return builder.toBytes();
}

/// Returns true if [data] looks like an Art-Net ArtPollReply packet.
bool isArtPollReply(Uint8List data) {
  if (data.length < 10) return false;
  final header = String.fromCharCodes(data.sublist(0, 7));
  if (header != _artNetId) return false;
  final opCode = data[8] | (data[9] << 8); // OpCode is little-endian on the wire
  return opCode == _opPollReply;
}

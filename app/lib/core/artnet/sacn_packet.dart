/// ANSI E1.31 (sACN) data packet construction.
///
/// sACN is the other protocol every node, console and lighting program on
/// the market speaks — the EasyNode included. Compared with Art-Net it adds
/// two things worth having: multicast, so a node subscribes to the
/// universes it cares about instead of everyone being addressed by IP, and
/// a priority field, so two sources on the same universe merge predictably
/// instead of fighting.
///
/// The packet is a fixed 638 bytes made of three nested "PDU" layers (root,
/// framing, DMP), each carrying its own length field. Everything is
/// big-endian, unlike Art-Net.
library;

import 'dart:convert';
import 'dart:typed_data';

/// E1.31 listens here. Unlike Art-Net's 6454 this is not configurable in
/// practice — receivers only join this port.
const sacnPort = 5568;

const _preambleSize = 0x0010;
const _postambleSize = 0x0000;
const _acnPacketIdentifier = <int>[
  0x41, 0x53, 0x43, 0x2d, 0x45, 0x31, 0x2e, 0x31,
  0x37, 0x00, 0x00, 0x00, // "ASC-E1.17\0\0\0"
];
const _vectorRootE131Data = 0x00000004;
const _vectorE131DataPacket = 0x00000002;
const _vectorDmpSetProperty = 0x02;

/// Total packet length with a full 512-slot universe.
const _packetLength = 638;

/// The multicast group carrying [universe] — `239.255.<high>.<low>`, as
/// mandated by E1.31 §9.3.1. Sending here means any node configured for
/// that universe receives it without the app knowing its IP.
String sacnMulticastAddress(int universe) {
  final u = universe.clamp(1, 63999);
  return '239.255.${(u >> 8) & 0xFF}.${u & 0xFF}';
}

/// Builds one E1.31 data packet for [universe].
///
/// [cid] is the sender's stable 16-byte component identifier: receivers use
/// it to tell sources apart when merging, so it has to stay the same for
/// the life of the app run. [sourceName] is what shows up in a console's
/// source list. [sequence] must increment per universe and wrap at 255 —
/// receivers use it to drop out-of-order UDP.
///
/// [priority] is 0-200 (100 is the E1.31 default). A higher-priority source
/// wins outright; equal priorities merge according to the receiver's rules.
Uint8List buildSacnDataPacket({
  required int universe,
  required int sequence,
  required Uint8List dmxData,
  required Uint8List cid,
  required String sourceName,
  int priority = 100,
  bool previewData = false,
  bool streamTerminated = false,
}) {
  assert(cid.length == 16, 'CID must be exactly 16 bytes');
  assert(dmxData.length <= 512, 'DMX data cannot exceed 512 channels');

  final packet = Uint8List(_packetLength);
  final view = ByteData.view(packet.buffer);

  // ---- Root layer ----
  view.setUint16(0, _preambleSize);
  view.setUint16(2, _postambleSize);
  packet.setRange(4, 16, _acnPacketIdentifier);
  // Flags (0x7) + length of everything from byte 16 onwards.
  view.setUint16(16, 0x7000 | (_packetLength - 16));
  view.setUint32(18, _vectorRootE131Data);
  packet.setRange(22, 38, cid);

  // ---- Framing layer ----
  view.setUint16(38, 0x7000 | (_packetLength - 38));
  view.setUint32(40, _vectorE131DataPacket);
  // 64-byte null-terminated source name, UTF-8, truncated if need be.
  final nameBytes = _utf8Truncated(sourceName, 63);
  packet.setRange(44, 44 + nameBytes.length, nameBytes);
  packet[108] = priority.clamp(0, 200);
  view.setUint16(109, 0); // Synchronization address: unused.
  packet[111] = sequence & 0xFF;
  packet[112] = (previewData ? 0x80 : 0) | (streamTerminated ? 0x40 : 0);
  view.setUint16(113, universe);

  // ---- DMP layer ----
  view.setUint16(115, 0x7000 | (_packetLength - 115));
  packet[117] = _vectorDmpSetProperty;
  packet[118] = 0xA1; // Address type & data type.
  view.setUint16(119, 0x0000); // First property address.
  view.setUint16(121, 0x0001); // Address increment.
  // Property value count = 512 slots + the start code byte.
  view.setUint16(123, 513);
  packet[125] = 0x00; // DMX512-A null start code.
  packet.setRange(126, 126 + dmxData.length, dmxData);

  return packet;
}

/// UTF-8 encodes [text] into at most [maxBytes] bytes without splitting a
/// character — the source name field is fixed-width and null-terminated.
Uint8List _utf8Truncated(String text, int maxBytes) {
  var candidate = text;
  while (candidate.isNotEmpty) {
    final bytes = utf8.encode(candidate);
    if (bytes.length <= maxBytes) return Uint8List.fromList(bytes);
    candidate = candidate.substring(0, candidate.length - 1);
  }
  return Uint8List(0);
}

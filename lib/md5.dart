import 'dart:math' as math;
import 'dart:typed_data';

/// MD5 (RFC 1321) — нужен для сопоставления вложений Evernote (ENEX) по хэшу.
/// Не используется для защиты данных.
String md5Hex(List<int> data) {
  const s = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const mask = 0xFFFFFFFF;
  final k = List<int>.generate(64, (i) => (math.sin(i + 1.0).abs() * 4294967296).floor() & mask);
  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  final len = data.length;
  final padLen = ((len + 8) ~/ 64 + 1) * 64;
  final buf = Uint8List(padLen);
  buf.setRange(0, len, data);
  buf[len] = 0x80;
  final bits = len * 8;
  for (var i = 0; i < 8; i++) {
    buf[padLen - 8 + i] = (bits >> (8 * i)) & 0xFF;
  }
  final m = List<int>.filled(16, 0);
  for (var off = 0; off < padLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      m[i] = buf[off + 4 * i] |
          (buf[off + 4 * i + 1] << 8) |
          (buf[off + 4 * i + 2] << 16) |
          (buf[off + 4 * i + 3] << 24);
    }
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = ((b & c) | ((~b & mask) & d)) & mask;
        g = i;
      } else if (i < 32) {
        f = ((d & b) | ((~d & mask) & c)) & mask;
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = (b ^ c ^ d) & mask;
        g = (3 * i + 5) % 16;
      } else {
        f = (c ^ (b | (~d & mask))) & mask;
        g = (7 * i) % 16;
      }
      f = (f + a + k[i] + m[g]) & mask;
      a = d;
      d = c;
      c = b;
      b = (b + (((f << s[i]) | (f >> (32 - s[i]))) & mask)) & mask;
    }
    a0 = (a0 + a) & mask;
    b0 = (b0 + b) & mask;
    c0 = (c0 + c) & mask;
    d0 = (d0 + d) & mask;
  }
  String le(int v) =>
      [for (var i = 0; i < 4; i++) ((v >> (8 * i)) & 0xFF).toRadixString(16).padLeft(2, '0')].join();
  return le(a0) + le(b0) + le(c0) + le(d0);
}

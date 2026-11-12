import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

List<int> base32Decode(String s) {
  const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final clean = s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
  final out = <int>[];
  var bits = 0;
  var val = 0;
  for (final ch in clean.split('')) {
    val = (val << 5) | a.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.add((val >> (bits - 8)) & 0xFF);
      bits -= 8;
      val &= (1 << bits) - 1;
    }
  }
  return out;
}

String extractSecret(String input) {
  final s = input.trim();
  if (s.startsWith('otpauth://')) {
    final u = Uri.tryParse(s);
    return u?.queryParameters['secret'] ?? '';
  }
  return s;
}

Future<String> totpCode(String secret,
    {DateTime? at, int digits = 6, int period = 30}) async {
  final bytes = base32Decode(extractSecret(secret));
  if (bytes.isEmpty) return '';
  final t = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 ~/ period;
  final msg = ByteData(8);
  msg.setUint32(0, (t >> 32) & 0xFFFFFFFF);
  msg.setUint32(4, t & 0xFFFFFFFF);
  final mac = await Hmac.sha1()
      .calculateMac(msg.buffer.asUint8List(), secretKey: SecretKey(bytes));
  final h = mac.bytes;
  final o = h[h.length - 1] & 0x0f;
  final bin = ((h[o] & 0x7f) << 24) |
      ((h[o + 1] & 0xff) << 16) |
      ((h[o + 2] & 0xff) << 8) |
      (h[o + 3] & 0xff);
  final code = bin % pow(10, digits).toInt();
  return code.toString().padLeft(digits, '0');
}

int totpSecondsLeft({int period = 30}) =>
    period - (DateTime.now().millisecondsSinceEpoch ~/ 1000) % period;

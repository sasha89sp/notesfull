import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// AES-256-GCM + PBKDF2-HMAC-SHA256 (100 000 итераций).
class Crypto {
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<SecretKey> deriveKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Ключ с фиксированной солью: одинаков на всех устройствах при одном пароле.
  static Future<SecretKey> deriveFixed(String password, String salt) =>
      deriveKey(password, utf8.encode(salt));

  /// Результат: nonce(12) + шифртекст + mac(16)
  static Future<Uint8List> encrypt(SecretKey key, List<int> data) async {
    final box = await _aes.encrypt(data, secretKey: key);
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Uint8List> decrypt(SecretKey key, List<int> data) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }
}

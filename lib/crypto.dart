import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

Future<List<int>> _deriveIso(List<dynamic> a) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  final k = await pbkdf2.deriveKeyFromPassword(
      password: a[0] as String, nonce: (a[1] as List).cast<int>());
  return k.extractBytes();
}

Future<Uint8List> _encIso(List<dynamic> a) async {
  final box = await AesGcm.with256bits()
      .encrypt(a[1] as Uint8List, secretKey: SecretKey(a[0] as List<int>));
  return Uint8List.fromList(box.concatenation());
}

Future<Uint8List> _decIso(List<dynamic> a) async {
  final box = SecretBox.fromConcatenation(a[1] as Uint8List,
      nonceLength: 12, macLength: 16);
  final clear = await AesGcm.with256bits()
      .decrypt(box, secretKey: SecretKey(a[0] as List<int>));
  return Uint8List.fromList(clear);
}

/// AES-256-GCM + PBKDF2-HMAC-SHA256 (100 000 итераций).
class Crypto {
  static final AesGcm _aes = AesGcm.with256bits();

  /// Тяжёлая операция (PBKDF2) выполняется в отдельном потоке, чтобы не вешать интерфейс.
  static Future<SecretKey> deriveKey(String password, List<int> salt) async {
    final bytes = await compute(_deriveIso, <dynamic>[password, salt]);
    return SecretKey(bytes);
  }

  /// Данные крупнее этого порога шифруются в отдельном потоке.
  static const int _big = 64 * 1024;

  /// Ключ с фиксированной солью: одинаков на всех устройствах при одном пароле.
  static Future<SecretKey> deriveFixed(String password, String salt) =>
      deriveKey(password, utf8.encode(salt));

  /// Результат: nonce(12) + шифртекст + mac(16)
  static Future<Uint8List> encrypt(SecretKey key, List<int> data) async {
    if (data.length > _big) {
      return compute(_encIso,
          <dynamic>[await key.extractBytes(), Uint8List.fromList(data)]);
    }
    final box = await _aes.encrypt(data, secretKey: key);
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Uint8List> decrypt(SecretKey key, List<int> data) async {
    if (data.length > _big) {
      return compute(_decIso,
          <dynamic>[await key.extractBytes(), Uint8List.fromList(data)]);
    }
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }
}

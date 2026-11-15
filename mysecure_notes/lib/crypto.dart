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

Future<Object?> _decJsonIso(List<dynamic> a) async {
  final box = SecretBox.fromConcatenation(a[1] as Uint8List,
      nonceLength: 12, macLength: 16);
  final clear = await AesGcm.with256bits()
      .decrypt(box, secretKey: SecretKey(a[0] as List<int>));
  return jsonDecode(utf8.decode(clear));
}

Future<Uint8List> _encJsonIso(List<dynamic> a) async {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(a[1])));
  final box = await AesGcm.with256bits()
      .encrypt(bytes, secretKey: SecretKey(a[0] as List<int>));
  return Uint8List.fromList(box.concatenation());
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

  /// Расшифровка и разбор JSON целиком в отдельном потоке (большие файлы не подвешивают интерфейс).
  static Future<Object?> decryptJson(SecretKey key, List<int> data) async {
    if (data.length > 32 * 1024) {
      return compute(_decJsonIso,
          <dynamic>[await key.extractBytes(), Uint8List.fromList(data)]);
    }
    return jsonDecode(utf8.decode(await decrypt(key, data)));
  }

  /// Сериализация и шифрование в отдельном потоке. [obj] — только списки, словари и примитивы.
  static Future<Uint8List> encryptJson(SecretKey key, Object obj) async {
    return compute(_encJsonIso, <dynamic>[await key.extractBytes(), obj]);
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

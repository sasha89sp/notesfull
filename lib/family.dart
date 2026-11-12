import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto.dart';
import 'models.dart';
import 'store.dart';
import 'sync.dart';

/// Семейный ключ: случайные 32 байта. Для каждого участника на сервере лежит
/// своя «обёртка» (/MySecureApp/keys/family_key_for_<uuid>.enc): ключ,
/// зашифрованный для публичного ключа участника (X25519 + HKDF + AES-GCM).
/// Расшифровать обёртку может только владелец соответствующего приватного ключа.
class FamilyKeys {
  static final X25519 _x = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const String keysDir = '${SyncService.root}/keys';

  static String fileFor(String uuid) => 'family_key_for_$uuid.enc';

  static Future<void> ensureKeyPair(Store s) async {
    final st = s.settings;
    if (st.kpPriv.isNotEmpty && st.kpPub.isNotEmpty) return;
    final kp = await _x.newKeyPair();
    final priv = await kp.extractPrivateKeyBytes();
    final pub = await kp.extractPublicKey();
    st.kpPriv = base64Encode(priv);
    st.kpPub = base64Encode(pub.bytes);
    await s.saveSettings();
  }

  static Future<SecretKey> _wrapKey(SecretKey shared) => _hkdf.deriveKey(
        secretKey: shared,
        nonce: const <int>[],
        info: utf8.encode('mysecure-family-wrap-v1'),
      );

  static Future<Uint8List> wrap(List<int> familyKey, String pubB64) async {
    final eph = await _x.newKeyPair();
    final remote =
        SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519);
    final shared =
        await _x.sharedSecretKey(keyPair: eph, remotePublicKey: remote);
    final k = await _wrapKey(shared);
    final ephPub = (await eph.extractPublicKey()).bytes;
    final enc = await Crypto.encrypt(k, familyKey);
    return Uint8List.fromList([...ephPub, ...enc]);
  }

  static Future<List<int>> unwrap(Uint8List data, Settings st) async {
    if (data.length < 33 + 28) throw 'Повреждённая обёртка ключа';
    final ephPub = data.sublist(0, 32);
    final enc = data.sublist(32);
    final kp = SimpleKeyPairData(
      base64Decode(st.kpPriv),
      publicKey:
          SimplePublicKey(base64Decode(st.kpPub), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final shared = await _x.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final k = await _wrapKey(shared);
    return Crypto.decrypt(k, enc);
  }

  /// Создать новый семейный ключ и выдать его себе.
  static Future<void> createFamily(Store s) async {
    final st = s.settings;
    if (st.familyPass.isNotEmpty) {
      throw 'Уже задан семейный пароль. Очистите его, чтобы перейти на ключи';
    }
    if (st.famKey.isNotEmpty) throw 'Семейный ключ уже есть';
    final r = Random.secure();
    final key = List<int>.generate(32, (_) => r.nextInt(256));
    await ensureKeyPair(s);
    st.famKey = base64Encode(key);
    await s.saveSettings();
    await grant(s, st.profileId, st.kpPub);
  }

  /// Выдать ключ участнику (по его публичному ключу из профиля).
  static Future<void> grant(Store s, String uuid, String pubB64) async {
    final st = s.settings;
    if (st.famKey.isEmpty) throw 'У вас нет семейного ключа';
    final dav = Dav(st.url, st.user, st.pass);
    await dav.mkcol(SyncService.root);
    await dav.mkcol(keysDir);
    await dav.putAtomic('$keysDir/${fileFor(uuid)}',
        await wrap(base64Decode(st.famKey), pubB64));
  }

  /// uuid участников, которым ключ уже выдан.
  static Future<Set<String>> granted(Store s) async {
    final st = s.settings;
    final dav = Dav(st.url, st.user, st.pass);
    final names = await dav.list(keysDir);
    final out = <String>{};
    for (final n in names) {
      final m = RegExp(r'^family_key_for_(.+)\.enc$').firstMatch(n);
      if (m != null) out.add(m.group(1)!);
    }
    return out;
  }

  /// Если для нас на сервере лежит обёртка — забираем ключ.
  static Future<bool> fetchMine(Dav dav, Store s) async {
    final st = s.settings;
    if (st.famKey.isNotEmpty || st.kpPriv.isEmpty) return st.famKey.isNotEmpty;
    final b = await dav.get('$keysDir/${fileFor(st.profileId)}');
    if (b == null) return false;
    try {
      final key = await unwrap(b, st);
      st.famKey = base64Encode(key);
      await s.saveSettings();
      return true;
    } catch (_) {
      return false;
    }
  }
}

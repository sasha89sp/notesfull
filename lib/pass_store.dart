import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'crypto.dart';
import 'models.dart';
import 'store.dart';
import 'sync.dart';
import 'util.dart';

/// Хранилище паролей: отдельный мастер-пароль, отдельный ключ, автоблокировка.
class PassStore extends ChangeNotifier {
  final Store store;
  PassStore(this.store);

  SecretKey? key;
  SecretKey? syncKey;
  List<PassEntry> entries = [];
  bool exists = false;
  String syncStatus = '';
  Timer? _lockTimer;
  Timer? _syncTimer;
  Future<void> _chain = Future.value();

  bool get unlocked => key != null;

  File _f(String n) => File('${store.dir.path}${Platform.pathSeparator}$n');

  Future<void> init() async {
    exists = await _f('passvault.json').exists();
  }

  Future<void> create(String pw) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final k = await Crypto.deriveKey(pw, salt);
    syncKey = await Crypto.deriveFixed(pw, 'mysecure-pass-sync-v1');
    final check = await Crypto.encrypt(k, utf8.encode('ok'));
    await writeAtomic(
      _f('passvault.json'),
      utf8.encode(jsonEncode({
        'salt': base64Encode(salt),
        'check': base64Encode(check),
      })),
    );
    key = k;
    entries = [];
    exists = true;
    await save();
    touch();
    notifyListeners();
    syncSoon();
  }

  Future<bool> unlock(String pw) async {
    final m = jsonDecode(await _f('passvault.json').readAsString())
        as Map<String, dynamic>;
    final k = await Crypto.deriveKey(pw, base64Decode(m['salt'] as String));
    try {
      final ok = await Crypto.decrypt(k, base64Decode(m['check'] as String));
      if (utf8.decode(ok) != 'ok') return false;
    } catch (_) {
      return false;
    }
    final f = _f('passwords.enc');
    var list = <PassEntry>[];
    if (await f.exists()) {
      final data = await Crypto.decrypt(k, await f.readAsBytes());
      list = (jsonDecode(utf8.decode(data)) as List)
          .map((e) => PassEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    key = k;
    syncKey = await Crypto.deriveFixed(pw, 'mysecure-pass-sync-v1');
    entries = list;
    touch();
    notifyListeners();
    syncSoon();
    return true;
  }

  void lock() {
    _lockTimer?.cancel();
    key = null;
    syncKey = null;
    entries = [];
    notifyListeners();
  }

  /// Любое действие пользователя перезапускает таймер автоблокировки.
  void touch() {
    _lockTimer?.cancel();
    if (!unlocked) return;
    _lockTimer = Timer(Duration(seconds: store.settings.autoLock), lock);
  }

  Future<void> save() {
    _chain = _chain.then((_) async {
      final k = key;
      if (k == null) return;
      final data =
          utf8.encode(jsonEncode(entries.map((e) => e.toJson()).toList()));
      await writeAtomic(_f('passwords.enc'), await Crypto.encrypt(k, data));
    }).catchError((Object e) {
      debugPrint('pass save error: $e');
    });
    return _chain;
  }

  void changed() {
    notifyListeners();
    save();
    touch();
    syncSoon();
  }

  void syncSoon() {
    _syncTimer?.cancel();
    if (!store.settings.syncConfigured) return;
    _syncTimer = Timer(const Duration(seconds: 3), () async {
      try {
        await SyncService.runPasswords(store, this);
        syncStatus = 'Пароли синхронизированы';
        await save();
        notifyListeners();
      } catch (e) {
        syncStatus = 'Ошибка синхронизации паролей: $e';
        notifyListeners();
      }
    });
  }

  List<PassEntry> get visible => entries.where((e) => !e.deleted).toList();
}

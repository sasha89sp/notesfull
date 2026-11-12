import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  final FlutterSecureStorage _ss = const FlutterSecureStorage();
  int _savedUntil = 0; // 0 — не сохранён, -1 — до выхода из профиля, иначе время (мс)

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

  // ---------------------------------------------- «Сохранить пароль» на срок

  String get _kpw => 'pp_${store.curId}';
  String get _kexp => 'ppx_${store.curId}';

  bool get savedActive =>
      _savedUntil == -1 || (_savedUntil > 0 && nowMs() < _savedUntil);

  /// minutes: -1 — до выхода из профиля
  Future<void> rememberPassword(String pw, int minutes) async {
    final until = minutes < 0 ? -1 : nowMs() + minutes * 60000;
    try {
      await _ss.write(key: _kpw, value: pw);
      await _ss.write(key: _kexp, value: until.toString());
      _savedUntil = until;
    } catch (_) {}
  }

  /// Сбросить сохранение вручную (забыть пароль раньше срока).
  Future<void> forgetSaved() async {
    _savedUntil = 0;
    try {
      await _ss.delete(key: _kpw);
      await _ss.delete(key: _kexp);
    } catch (_) {}
    notifyListeners();
  }

  /// Если срок сохранения не истёк, открываем хранилище без запроса пароля.
  Future<bool> tryAutoUnlock() async {
    if (unlocked || !exists) return unlocked;
    try {
      final exp = int.tryParse(await _ss.read(key: _kexp) ?? '') ?? 0;
      if (exp == 0) return false;
      if (exp != -1 && nowMs() >= exp) {
        await forgetSaved();
        return false;
      }
      final pw = await _ss.read(key: _kpw);
      if (pw == null) return false;
      _savedUntil = exp;
      return await unlock(pw);
    } catch (_) {
      return false;
    }
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
    _lockTimer = Timer(Duration(seconds: store.settings.autoLock), () {
      // пока действует сохранённый пароль, повторно его не спрашиваем
      if (savedActive) {
        touch();
      } else {
        lock();
      }
    });
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

  List<PassEntry> get visible =>
      entries.where((e) => !e.deleted && !e.isFolder).toList();

  /// Все папки: из записей и из служебных записей пустых папок.
  List<String> get folderNames {
    final set = <String>{};
    for (final e in entries) {
      if (!e.deleted && e.folder.isNotEmpty) set.add(e.folder);
    }
    final l = set.toList()..sort();
    return l;
  }

  void createFolder(String name) {
    final n = name.trim();
    if (n.isEmpty || folderNames.contains(n)) return;
    entries.add(PassEntry.create()
      ..isFolder = true
      ..folder = n);
    changed();
  }

  void renameFolder(String from, String to) {
    final n = to.trim();
    if (n.isEmpty || n == from) return;
    for (final e in entries) {
      if (e.folder == from && !e.deleted) {
        e.folder = n;
        e.updatedAt = nowMs();
      }
    }
    changed();
  }

  /// Удаление папки: записи не теряются, а переходят в «Без папки».
  void deleteFolder(String name) {
    for (final e in entries) {
      if (e.folder != name || e.deleted) continue;
      if (e.isFolder) {
        e.deleted = true;
      } else {
        e.folder = '';
      }
      e.updatedAt = nowMs();
    }
    changed();
  }
}

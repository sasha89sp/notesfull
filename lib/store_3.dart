// ▸ Часть store.dart: Главное хранилище состояния: профили, ключи, заметки, события, чат, сохранение, поиск, блокировки модулей, зап  [содержит: ExtStore2]
part of 'store.dart';

extension ExtStore2 on Store {

  // ------------------------------------------------------------ вход

  Future<void> create(String pw) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final k = await Crypto.deriveKey(pw, salt);
    final sk = await Crypto.deriveFixed(pw, _syncSalt);
    final check = await Crypto.encrypt(k, utf8.encode('ok'));
    await writeAtomic(
      _f('vault.json'),
      utf8.encode(jsonEncode({
        'salt': base64Encode(salt),
        'check': base64Encode(check),
      })),
    );
    key = k;
    syncKey = sk;
    notes = [];
    events = [];
    comments = [];
    folders = [];
    history = [];
    settings = Settings(profileId: newId());
    await save();
  }

  Future<bool> unlock(String pw) async {
    final m = jsonDecode(await _f('vault.json').readAsString())
        as Map<String, dynamic>;
    final salt = base64Decode(m['salt'] as String);
    final k = await Crypto.deriveKey(pw, salt);
    try {
      final ok = await Crypto.decrypt(k, base64Decode(m['check'] as String));
      if (utf8.decode(ok) != 'ok') return false;
    } catch (_) {
      return false;
    }
    key = k;
    syncKey = await Crypto.deriveFixed(pw, _syncSalt);
    await _load();
    return true;
  }

  Future<void> _load() async {
    final k = key!;
    // основной файл, затем временный и резервный: сбой при записи не теряет данные
    Future<dynamic> readJson(String n) async {
      final f = _f(n);
      final v = await readValid<dynamic>(f, (b) async {
        return Crypto.decryptJson(k, b);
      });
      if (v == null && await f.exists()) {
        AppLog.I.e('store', 'Файл $n повреждён и резервной копии нет');
      }
      return v;
    }

    final n = await readJson('notes.enc');
    notes = n == null
        ? []
        : (n as List)
            .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    final e = await readJson('events.enc');
    events = e == null
        ? []
        : (e as List)
            .map((x) => CalEvent.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
    final c = await readJson('comments.enc');
    comments = c == null
        ? []
        : (c as List)
            .map((x) => Comment.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
    final fo = await readJson('folders.enc');
    folders = fo == null
        ? []
        : (fo as List)
            .map((x) => NoteFolder.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
    final s = await readJson('settings.enc');
    settings = s == null
        ? Settings()
        : Settings.fromJson(Map<String, dynamic>.from(s as Map));
    if (settings.profileId.isEmpty) {
      settings.profileId = newId();
      await saveSettings();
    }
    await _adaptToPlatform();
    AppLog.I.verbose = settings.verboseLog;
    await Groups.migrateLegacy(this);
    final h = await readJson('synchist.enc');
    history = h == null
        ? []
        : (h as List)
            .map((x) => SyncRecord.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
  } // когда модуль был разблокирован / последний раз активен

  /// Модуль закрыт блокировкой? Работает отдельно для «Общая папка» и «Пароли».
  bool moduleLocked(String m) {
    final to = settings.modLock[m];
    if (to == null) return false;
    final t = _modOk[m];
    if (t == null) return true;
    return nowMs() - t > to * 1000;
  }

  /// Отметка активности: вызывается, пока модуль открыт (и при выходе из него).
  void moduleTouch(String m) => _modOk[m] = nowMs();

  void moduleLock(String m) => _modOk.remove(m);

  Future<bool> unlockModule(String m) async {
    try {
      final la = LocalAuthentication();
      if (!await la.isDeviceSupported()) return false;
      final ok = await la.authenticate(
        localizedReason: 'Подтвердите доступ к разделу',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) moduleTouch(m);
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ биометрия

  Future<bool> bioAvailable() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> bioStored() async {
    try {
      return (await _ss.read(key: _bk('k'))) != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableBiometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Подтвердите включение входа по биометрии',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!ok) return false;
      await _ss.write(key: _bk('k'), value: base64Encode(await key!.extractBytes()));
      await _ss.write(
          key: _bk('sk'), value: base64Encode(await syncKey!.extractBytes()));
      settings.bio = true;
      await saveSettings();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disableBiometric() async {
    try {
      await _ss.delete(key: _bk('k'));
      await _ss.delete(key: _bk('sk'));
    } catch (_) {}
    settings.bio = false;
    await saveSettings();
  }

  /// Тихая разблокировка для фоновой синхронизации (без диалога биометрии):
  /// работает только если ключи ранее сохранены в защищённом хранилище.
  Future<bool> unlockSilent() async {
    try {
      final k = await _ss.read(key: _bk('k'));
      final sk = await _ss.read(key: _bk('sk'));
      if (k == null || sk == null) return false;
      key = SecretKey(base64Decode(k));
      syncKey = SecretKey(base64Decode(sk));
      await _load();
      return true;
    } catch (_) {
      key = null;
      syncKey = null;
      return false;
    }
  }

  Future<bool> unlockBio() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Разблокируйте заметки',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!ok) return false;
      final k = await _ss.read(key: _bk('k'));
      final sk = await _ss.read(key: _bk('sk'));
      if (k == null || sk == null) return false;
      key = SecretKey(base64Decode(k));
      syncKey = SecretKey(base64Decode(sk));
      await _load();
      return true;
    } catch (_) {
      key = null;
      syncKey = null;
      return false;
    }
  }

  // ------------------------------------------------------------ сохранение

  Future<void> _saveJson(String name, Object data) {
    _chain = _chain.then((_) async {
      final k = key;
      if (k == null) return;
      // небольшие данные шифруем сразу, большие — вместе с сериализацией в отдельном потоке
      final Uint8List enc;
      if (data is List && data.length > 300) {
        enc = await Crypto.encryptJson(k, data);
      } else {
        enc = await Crypto.encrypt(k, utf8.encode(jsonEncode(data)));
      }
      await writeAtomic(_f(name), enc);
    }).catchError((Object e) {
      debugPrint('save error: $e');
    });
    return _chain;
  }

  Future<void> saveNotes() =>
      _saveJson('notes.enc', notes.map((n) => n.toJson()).toList());
  Future<void> saveEvents() =>
      _saveJson('events.enc', events.map((e) => e.toJson()).toList());
  Future<void> saveComments() =>
      _saveJson('comments.enc', comments.map((c) => c.toJson()).toList());
  Future<void> saveChat() =>
      _saveJson('chat.enc', chat.map((c) => c.toJson()).toList());
}

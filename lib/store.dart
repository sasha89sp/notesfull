import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'applog.dart';
import 'crypto.dart';
import 'google.dart';
import 'models.dart';
import 'sync.dart';
import 'synchist.dart';
import 'util.dart';

class ProfileInfo {
  String id;
  String name;
  String kind; // local | online
  String dir; // пусто = корневая папка (профиль из старой версии)
  ProfileInfo(
      {required this.id, this.name = '', this.kind = 'local', this.dir = ''});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'kind': kind, 'dir': dir};
  factory ProfileInfo.fromJson(Map<String, dynamic> j) => ProfileInfo(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        kind: (j['kind'] ?? 'local') as String,
        dir: (j['dir'] ?? '') as String,
      );
}

class Store extends ChangeNotifier {
  late Directory baseDir;
  late Directory dir; // папка текущего профиля
  List<ProfileInfo> profiles = [];
  String curId = '';
  bool wantPicker = false;
  SecretKey? key; // локальный ключ (случайная соль)
  SecretKey? syncKey; // ключ синхронизации личных данных (одинаков на устройствах)
  List<Note> notes = [];
  List<CalEvent> events = [];
  List<Comment> comments = [];
  List<NoteFolder> folders = [];
  Settings settings = Settings();
  bool syncing = false;
  String status = '';
  String progressText = '';
  double? progress;
  List<SyncRecord> history = [];
  CancelToken? _tok;
  VoidCallback? onEventsChanged;

  SecretKey? _fk;
  String _fkPass = '';
  Future<void> _chain = Future.value();
  Timer? _debounce;
  final FlutterSecureStorage _ss = const FlutterSecureStorage();

  String get author => settings.author.isEmpty ? 'Я' : settings.author;
  String get profileId => settings.profileId;

  Future<void> init() async {
    baseDir = await getApplicationSupportDirectory();
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    dir = baseDir;
    await _loadIndex();
  }

  File _f(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  File get _indexFile =>
      File('${baseDir.path}${Platform.pathSeparator}profiles.json');

  Future<void> _loadIndex() async {
    profiles = [];
    try {
      if (await _indexFile.exists()) {
        final j = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
        profiles = ((j['profiles'] ?? []) as List)
            .map((e) => ProfileInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        curId = (j['last'] ?? '') as String;
      } else if (await File('${baseDir.path}${Platform.pathSeparator}vault.json')
          .exists()) {
        // хранилище из прошлой версии становится первым профилем
        profiles = [ProfileInfo(id: 'legacy')];
        curId = 'legacy';
        await _saveIndex();
      }
    } catch (e) {
      AppLog.I.e('profiles', 'Не удалось прочитать список профилей: $e');
    }
    if (profiles.isNotEmpty &&
        !profiles.any((p) => p.id == curId)) {
      curId = profiles.first.id;
    }
    if (curId.isNotEmpty) selectProfile(curId, save: false);
  }

  Future<void> _saveIndex() => writeAtomic(
      _indexFile,
      utf8.encode(jsonEncode({
        'last': curId,
        'profiles': profiles.map((p) => p.toJson()).toList(),
      })));

  Future<bool> hasVault() async => profiles.isNotEmpty;

  ProfileInfo? profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  ProfileInfo? profileByName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final p in profiles) {
      if (p.name.trim().toLowerCase() == n) return p;
    }
    return null;
  }

  void selectProfile(String id, {bool save = true}) {
    final p = profileById(id);
    if (p == null) return;
    curId = id;
    dir = p.dir.isEmpty
        ? baseDir
        : Directory('${baseDir.path}${Platform.pathSeparator}${p.dir}');
    if (save) _saveIndex();
  }

  /// Создать новый профиль (локальный или онлайн) и войти в него.
  Future<void> createProfile(String name, String pw,
      {String kind = 'local',
      String url = '',
      String user = '',
      String pass = ''}) async {
    final id = newId();
    final p = ProfileInfo(id: id, name: name, kind: kind, dir: 'p_$id');
    profiles.add(p);
    selectProfile(id, save: false);
    await dir.create(recursive: true);
    await create(pw);
    settings.author = name;
    if (kind == 'online') {
      settings.url = url;
      settings.user = user;
      settings.pass = pass;
    }
    await saveSettings();
    await _saveIndex();
    AppLog.I.i('profile', 'Создан профиль «$name» ($kind)');
  }

  Future<void> renameCurrent(String name) async {
    final p = profileById(curId);
    if (p == null || name.trim().isEmpty) return;
    p.name = name.trim();
    await _saveIndex();
  }

  String _kid(String base, String id) => id == 'legacy' || id.isEmpty ? base : '${base}_$id';
  String _bk(String base) => _kid(base, curId);

  Future<void> rememberLogin(String pw) async {
    try {
      await _ss.write(key: _bk('rpw'), value: pw);
    } catch (_) {}
  }

  Future<String?> rememberedPw(String id) async {
    try {
      return await _ss.read(key: _kid('rpw', id));
    } catch (_) {
      return null;
    }
  }

  Future<void> forgetLogin() async {
    try {
      await _ss.delete(key: _bk('rpw'));
    } catch (_) {}
  }

  /// Выход из профиля: данные в памяти очищаются, на диске остаются.
  Future<void> logout({bool picker = false}) async {
    cancelSync();
    _debounce?.cancel();
    for (var i = 0; i < 100 && syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _chain;
    key = null;
    syncKey = null;
    notes = [];
    events = [];
    comments = [];
    folders = [];
    history = [];
    settings = Settings();
    _fk = null;
    status = '';
    wantPicker = picker;
    AppLog.I.i('profile', 'Выход из профиля');
    notifyListeners();
  }

  // ------------------------------------------------------------ вход

  Future<void> create(String pw) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final k = await Crypto.deriveKey(pw, salt);
    final sk = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
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
    syncKey = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
    await _load();
    return true;
  }

  Future<void> _load() async {
    final k = key!;
    Future<dynamic> readJson(String n) async {
      final f = _f(n);
      if (!await f.exists()) return null;
      final data = await Crypto.decrypt(k, await f.readAsBytes());
      return jsonDecode(utf8.decode(data));
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
    AppLog.I.verbose = settings.verboseLog;
    final h = await readJson('synchist.enc');
    history = h == null
        ? []
        : (h as List)
            .map((x) => SyncRecord.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
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
      final bytes = utf8.encode(jsonEncode(data));
      await writeAtomic(_f(name), await Crypto.encrypt(k, bytes));
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
  Future<void> saveFolders() =>
      _saveJson('folders.enc', folders.map((f) => f.toJson()).toList());
  Future<void> saveSettings() => _saveJson('settings.enc', settings.toJson());

  Future<void> save() async {
    await saveNotes();
    await saveEvents();
    await saveComments();
    await saveFolders();
    await saveSettings();
  }

  void refresh() => notifyListeners();

  /// После изменения заметок
  void changed() {
    notifyListeners();
    saveNotes();
    schedSync();
  }

  void eventsChanged() {
    notifyListeners();
    saveEvents();
    onEventsChanged?.call();
    schedSync();
  }

  // ------------------------------------------------------------ папки заметок

  List<NoteFolder> childFolders(String parent) {
    final l = folders.where((f) => !f.deleted && f.parent == parent).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l;
  }

  NoteFolder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id && !f.deleted) return f;
    }
    return null;
  }

  /// Путь «Родитель / Папка»
  String folderPath(String id) {
    final parts = <String>[];
    var cur = id;
    var guard = 0;
    while (cur.isNotEmpty && guard++ < 50) {
      final f = folderById(cur);
      if (f == null) break;
      parts.insert(0, f.name);
      cur = f.parent;
    }
    return parts.join(' / ');
  }

  bool isInside(String id, String ancestor) {
    var cur = id;
    var guard = 0;
    while (cur.isNotEmpty && guard++ < 50) {
      if (cur == ancestor) return true;
      cur = folderById(cur)?.parent ?? '';
    }
    return false;
  }

  /// Число заметок в папке и всех вложенных.
  int notesIn(String id) => notes
      .where((n) => !n.deleted && n.folder.isNotEmpty && isInside(n.folder, id))
      .length;

  NoteFolder addFolder(String name, String parent) {
    final f = NoteFolder.create(name, parent);
    folders.add(f);
    foldersChanged();
    return f;
  }

  void renameFolder(NoteFolder f, String name) {
    f.name = name;
    f.updatedAt = nowMs();
    foldersChanged();
  }

  void moveFolder(NoteFolder f, String parent) {
    if (parent == f.id || isInside(parent, f.id)) return;
    f.parent = parent;
    f.updatedAt = nowMs();
    foldersChanged();
  }

  /// Удаление папки: вложенное (папки и заметки) переходит на уровень выше.
  void deleteFolder(NoteFolder f) {
    for (final c in folders.where((x) => x.parent == f.id && !x.deleted)) {
      c.parent = f.parent;
      c.updatedAt = nowMs();
    }
    for (final n in notes.where((n) => n.folder == f.id)) {
      n.folder = f.parent;
      n.updatedAt = nowMs();
    }
    f.deleted = true;
    f.updatedAt = nowMs();
    foldersChanged();
    changed();
  }

  void moveNote(Note n, String folder) {
    n.folder = folder;
    n.updatedAt = nowMs();
    changed();
  }

  void foldersChanged() {
    notifyListeners();
    saveFolders();
    schedSync();
  }

  void commentsChanged() {
    notifyListeners();
    saveComments();
    schedSync();
  }

  void schedSync() {
    _debounce?.cancel();
    if (settings.syncConfigured || settings.googleConfigured) {
      _debounce = Timer(const Duration(seconds: 5), () => syncAll());
    }
  }

  // ------------------------------------------------------------ поиск

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool isMine(Note n) =>
      (n.authorId.isNotEmpty && n.authorId == settings.profileId) ||
      (n.authorId.isEmpty && n.author == author);

  Future<SecretKey?> familyKey() async {
    if (settings.famKey.isNotEmpty) {
      return SecretKey(base64Decode(settings.famKey));
    }
    final p = settings.familyPass;
    if (p.isEmpty) return null;
    if (_fk == null || _fkPass != p) {
      _fk = await Crypto.deriveFixed(p, 'mysecure-family-v1');
      _fkPass = p;
    }
    return _fk;
  }

  // ------------------------------------------------------------ вложения

  Directory get _attDir =>
      Directory('${dir.path}${Platform.pathSeparator}attachments');

  File attFile(String id) =>
      File('${_attDir.path}${Platform.pathSeparator}$id.enc');

  bool hasAttachment(String id) => attFile(id).existsSync();

  Future<void> writeAttachment(String id, List<int> plain) async {
    if (!await _attDir.exists()) await _attDir.create(recursive: true);
    await writeAtomic(attFile(id), await Crypto.encrypt(key!, plain));
  }

  Future<String> addAttachment(List<int> plain) async {
    final id = newId();
    await writeAttachment(id, plain);
    return id;
  }

  Future<Uint8List?> readAttachment(String id) async {
    final f = attFile(id);
    if (!await f.exists()) return null;
    try {
      return await Crypto.decrypt(key!, await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ синхронизация

  SyncRecord? get lastSync => history.isEmpty ? null : history.last;

  Future<void> addHistory(SyncRecord r) async {
    history.add(r);
    if (history.length > 100) history.removeRange(0, history.length - 100);
    await _saveJson('synchist.enc', history.map((x) => x.toJson()).toList());
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await _saveJson('synchist.enc', <dynamic>[]);
    notifyListeners();
  }

  void setProgress(String text, [double? frac]) {
    progressText = text;
    progress = frac;
    notifyListeners();
  }

  /// Прервать текущую синхронизацию; локальные данные не теряются.
  void cancelSync() {
    final t = _tok;
    if (t != null && !t.cancelled) {
      t.cancelled = true;
      progressText = 'Отмена…';
      notifyListeners();
    }
  }

  Future<void> syncAll() async {
    if (syncing || key == null) return;
    if (!settings.syncConfigured && !settings.googleConfigured) return;
    syncing = true;
    final tok = _tok = CancelToken();
    status = 'Синхронизация…';
    progressText = 'Подготовка…';
    progress = null;
    notifyListeners();
    final all = SyncStats();
    final rec = SyncRecord(at: nowMs(), status: 'ok');
    var failed = false;
    AppLog.I.i('sync', 'Старт синхронизации');

    try {
      if (settings.syncConfigured) {
        rec.targets.add('WebDAV');
        setProgress('WebDAV: обмен данными…');
        final r = SyncStats();
        try {
          await SyncService.run(this, r, tok);
        } catch (e, st) {
          if (e is SyncCancelled) rethrow;
          failed = true;
          r.log.add('WebDAV: ошибка — $e');
          AppLog.I.e('sync', 'WebDAV: $e', st);
        } finally {
          all.merge(r);
        }
      }
      tok.check();
      if (settings.googleConfigured) {
        rec.targets.add('Google Календарь');
        setProgress('Google Календарь…');
        final r = SyncStats();
        try {
          await GoogleCal.sync(this, r, tok);
        } catch (e, st) {
          if (e is SyncCancelled) rethrow;
          failed = true;
          r.log.add('Google: ошибка — $e');
          AppLog.I.e('sync', 'Google: $e', st);
        } finally {
          all.merge(r);
        }
      }
    } on SyncCancelled {
      rec.status = 'cancelled';
      AppLog.I.i('sync', 'Синхронизация отменена пользователем');
    }

    if (rec.status != 'cancelled') rec.status = failed ? 'error' : 'ok';
    rec.up = all.up;
    rec.down = all.down;
    rec.conflicts = all.conflicts;
    rec.log = all.log;
    AppLog.I.i('sync',
        '${rec.statusText}: отправлено ${all.upTotal}, получено ${all.downTotal}');

    syncing = false;
    _tok = null;
    progressText = '';
    progress = null;
    status = '${rec.when}: ${rec.statusText}';
    await save();
    await addHistory(rec);
    if (all.up.containsKey('events') || all.down.containsKey('events')) {
      onEventsChanged?.call();
    }
    notifyListeners();
  }

  Future<void> sync() => syncAll();
}

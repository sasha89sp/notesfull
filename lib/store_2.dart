// ▸ Часть store.dart: Главное хранилище состояния: профили, ключи, заметки, события, чат, сохранение, поиск, блокировки модулей, зап  [содержит: ExtStore1]
part of 'store.dart';

extension ExtStore1 on Store {

  String get author => settings.author.isEmpty ? 'Я' : settings.author;
  String get profileId => settings.profileId;

  /// Настройки, привязанные к устройству (пути, вид, панели, фоновая работа), не переносятся
  /// между платформами: после восстановления бэкапа с другой платформы они сбрасываются.
  Future<void> _adaptToPlatform() async {
    final me = Platform.operatingSystem;
    final st = settings;
    if (st.platform == me) return;
    if (st.platform.isNotEmpty) {
      st.uiMode = 'auto';
      st.paneOrder = ['side', 'list', 'detail'];
      st.paneW = {'side': 230, 'list': 330};
      st.bgSync = false;
      st.folderSyncs = [];
      st.dockItems = [];
      st.remapOn = false;
      st.dictGlobal = false;
      if (st.storage == 'local') st.localPath = '';
      AppLog.I.i('settings', 'Настройки перенесены с ${st.platform} на $me: локальные параметры сброшены');
    }
    st.platform = me;
    await saveSettings(touch: false);
  }

  Future<void> init() async {
    baseDir = await AppDirs.base();
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
      String pass = '',
      String storage = 'webdav',
      String folder = '/MySecureApp',
      String localPath = '',
      String uid = '',
      Map<String, dynamic>? remoteSettings}) async {
    final id = newId();
    final p = ProfileInfo(id: id, name: name, kind: kind, dir: 'p_$id', uid: uid);
    profiles.add(p);
    selectProfile(id, save: false);
    await dir.create(recursive: true);
    await create(pw);
    settings.author = name;
    if (kind == 'online') {
      settings.url = url;
      settings.user = user;
      settings.pass = pass;
      settings.storage = storage;
      settings.folder = folder;
      settings.localPath = localPath;
      settings.userId = uid;
      // внутренние настройки (календарь, ключи, модули…) приходят из облака сами
      if (remoteSettings != null) {
        settings = Accounts.applySettings(settings, remoteSettings);
        authorKeep(name);
      }
    }
    await _saveJson('settings.enc', settings.toJson());
    await _saveIndex();
    AppLog.I.i('profile', 'Создан профиль «$name» ($kind)');
  }

  void authorKeep(String name) {
    if (settings.author.isEmpty) settings.author = name;
  }

  /// Соль ключа синхронизации: у аккаунтов ASRbox своя, у старых профилей прежняя.
  String get _syncSalt {
    final u = profileById(curId)?.uid ?? '';
    return u.isEmpty ? 'mysecure-personal-sync-v1' : 'asrbox-sync-v2:$u';
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
    chat = [];
    chatLoaded = false;
    folders = [];
    history = [];
    settings = Settings();
    status = '';
    wantPicker = picker;
    AppLog.I.i('profile', 'Выход из профиля');
    notifyListeners();
  }

  /// Полный сброс профиля на этом устройстве: данные, ключи в защищённом хранилище и
  /// запись о профиле. Данные в облаке не затрагиваются.
  Future<void> resetProfile() async {
    final p = profileById(curId);
    final id = curId;
    final d = dir;
    final legacyRoot = p == null || p.dir.isEmpty;
    for (final k in ['rpw', 'k', 'sk']) {
      try {
        await _ss.delete(key: _kid(k, id));
      } catch (_) {}
    }
    await logout(picker: true);
    try {
      if (!legacyRoot) {
        if (await d.exists()) await d.delete(recursive: true);
      } else {
        await for (final e in d.list(followLinks: false)) {
          if (e is File) {
            final n = e.uri.pathSegments.last;
            if (n.endsWith('.enc') || n.endsWith('.bak') || n.endsWith('.tmp') ||
                n == 'vault.json' || n == 'passvault.json') {
              await e.delete();
            }
          } else if (e is Directory && e.uri.pathSegments.contains('attachments')) {
            await e.delete(recursive: true);
          }
        }
      }
    } catch (e) {
      AppLog.I.e('profile', 'Сброс: не удалось удалить файлы: $e');
    }
    profiles.removeWhere((x) => x.id == id);
    curId = profiles.isEmpty ? '' : profiles.first.id;
    await _saveIndex();
    AppLog.I.i('profile', 'Профиль сброшен');
    notifyListeners();
  }
}

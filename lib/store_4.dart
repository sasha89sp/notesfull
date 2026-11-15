part of 'store.dart';

extension ExtStore3 on Store {

  /// Загрузка переписки по требованию: отключённый модуль не тратит ресурсы.
  Future<void> ensureChat() async {
    if (chatLoaded || key == null) return;
    chatLoaded = true;
    try {
      final v = await readValid<dynamic>(_f('chat.enc'), (b) async {
        return jsonDecode(utf8.decode(await Crypto.decrypt(key!, b)));
      });
      chat = v == null
          ? []
          : (v as List)
              .map((x) => ChatMsg.fromJson(Map<String, dynamic>.from(x as Map)))
              .toList();
    } catch (e) {
      AppLog.I.e('chat', 'Не удалось прочитать чат: $e');
    }
  }

  Future<void> sendChat(String room, String text) async {
    await ensureChat();
    final gr = Groups.byId(settings, room);
    final nm = (gr == null || gr.myName.isEmpty) ? author : gr.myName;
    chat.add(ChatMsg.create(room, settings.profileId, nm, text));
    notifyListeners();
    await saveChat();
    // сразу отправляем сообщение, не дожидаясь отложенной синхронизации
    if (gr != null && !gr.removed) {
      try {
        await SyncChat.chatOnly(this, gr);
      } catch (e) {
        AppLog.I.e('chat', 'отправка: $e', null);
        schedSync();
      }
    } else {
      schedSync();
    }
  }

  Future<void> saveFolders() =>
      _saveJson('folders.enc', folders.map((f) => f.toJson()).toList());
  /// Сохранить настройки; отметка времени нужна, чтобы новые настройки
  /// выигрывали при синхронизации между устройствами.
  Future<void> saveSettings({bool touch = true}) {
    if (touch) settings.settingsUpdatedAt = nowMs();
    return _saveJson('settings.enc', settings.toJson());
  }

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

  void setViewDay(DateTime d, {String? view}) {
    viewDay = DateTime(d.year, d.month, d.day);
    if (view != null) calView = view;
    notifyListeners();
  }
  int get lastRunMs => _lastRun;

  void eventsChanged() {
    notifyListeners();
    saveEvents();
    onEventsChanged?.call();
    _gcalDirty = true;
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

  // ------------------------------------------------------------ режим интерфейса

  /// Десктопный вид: выбран вручную или (авто) на компьютере в широком окне.
  bool useDesktop(double width) {
    switch (settings.uiMode) {
      case 'desktop':
        return true;
      case 'mobile':
        return false;
      default:
        return (Platform.isWindows || Platform.isLinux || Platform.isMacOS) && width >= 900;
    }
  }

  // ------------------------------------------------------------ поиск по индексу

  /// Локальный индекс: нижний регистр текста каждой заметки, пересобирается только у изменённых.
  final Map<String, (int, String)> _sidx = {};

  String _searchText(Note n) {
    final e = _sidx[n.id];
    if (e != null && e.$1 == n.updatedAt) return e.$2;
    final t = '${n.title}\n${n.tags.join(' ')}\n${n.preview(100000)}'.toLowerCase();
    _sidx[n.id] = (n.updatedAt, t);
    return t;
  }

  /// Все слова запроса должны встречаться в заметке (в любом порядке).
  bool matches(Note n, String q) {
    final t = _searchText(n);
    for (final w in q.toLowerCase().split(RegExp(r'\s+'))) {
      if (w.isNotEmpty && !t.contains(w)) return false;
    }
    return true;
  }

  /// Прогрев индекса порциями в фоне, чтобы первый поиск был мгновенным.
  /// Без синхронизации корзину чистим только локально.
  void purgeTrashLocal() {
    if (settings.syncConfigured || settings.googleConfigured) return;
    final cut = nowMs() - kTrashDays * 24 * 3600 * 1000;
    notes.removeWhere((n) => n.deleted && n.updatedAt < cut);
  }

  Future<void> warmSearch() async {
    purgeTrashLocal();
    var i = 0;
    for (final n in List<Note>.of(notes)) {
      if (n.deleted) continue;
      _searchText(n);
      if (++i % 40 == 0) await Future<void>.delayed(Duration.zero);
    }
    _sidx.removeWhere((id, _) => !notes.any((n) => n.id == id));
  }

  // ------------------------------------------------------------ избранное и закрепление

  bool isFolderFav(String id) => settings.favorites.contains(id);
  bool isPinned(String id) => settings.pinned.contains(id);

  void toggleFolderFav(String id) {
    if (!settings.favorites.remove(id)) settings.favorites.add(id);
    saveSettings();
    notifyListeners();
    schedSync();
  }

  void togglePin(String id) {
    if (!settings.pinned.remove(id)) settings.pinned.add(id);
    saveSettings();
    notifyListeners();
    schedSync();
  }

  void foldersChanged() {
    notifyListeners();
    saveFolders();
    schedSync();
  }
}

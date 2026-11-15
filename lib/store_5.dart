part of 'store.dart';

extension ExtStore4 on Store {

  void commentsChanged() {
    notifyListeners();
    saveComments();
    schedSync();
  }

  void schedSync() {
    _debounce?.cancel();
    if (!settings.syncOnChange) return;
    if (settings.syncConfigured || settings.googleConfigured) {
      _debounce = Timer(const Duration(seconds: 5), () => syncAll(auto: true));
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

  /// Ход синхронизации. Интерфейс перерисовывается не чаще ~5 раз в секунду:
  /// иначе при тысячах событий календаря каждое сообщение пересобирает все экраны
  /// и приложение «зависает».
  void setProgress(String text, [double? frac]) {
    progressText = text;
    progress = frac;
    Net.stage(text);
    final t = nowMs();
    if (t - _lastProgressNotify < 200) return;
    _lastProgressNotify = t;
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

  /// Нужно ли сейчас обращаться к Google Календарю при автоматической синхронизации.
  bool _gcalDue() {
    if (_gcalDirty) return true;
    final m = settings.gcalEvery;
    return m > 0 && nowMs() - settings.gcalLast >= Duration(minutes: m).inMilliseconds;
  }

  /// [auto] — запуск по расписанию/событию (а не кнопкой): учитывает настройки
  /// «Синхронизация» и не трогает Google Календарь, пока не подошёл срок.
  Future<void> syncAll({bool auto = false}) async {
    if (syncing || key == null) return;
    if (!settings.syncConfigured && !settings.googleConfigured) return;
    if (auto && nowMs() - _lastRun < 60000) return; // не чаще раза в минуту
    _lastRun = nowMs();
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
          await SyncService.run(this, r, tok, auto: auto);
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
      if (settings.googleConfigured && (!auto || _gcalDue())) {
        rec.targets.add('Google Календарь');
        setProgress('Google Календарь…');
        final r = SyncStats();
        try {
          await GoogleSync.sync(this, r, tok);
          settings.gcalLast = nowMs();
          _gcalDirty = false;
        } catch (e, st) {
          if (e is SyncCancelled) rethrow;
          failed = true;
          r.log.add('Google: ошибка — $e');
          AppLog.I.e('sync', 'Google: $e', st);
        } finally {
          all.merge(r);
        }
      }
      tok.check();
      await IcalSub.syncDue(this); // подписки iCal: раз в 2 часа
    } on SyncCancelled {
      rec.status = 'cancelled';
      AppLog.I.i('sync', 'Синхронизация отменена пользователем');
    }

    if (notices.isNotEmpty) {
      final parts = <String>[];
      notices.forEach((g, v) {
        final x = <String>[];
        if (v[0] > 0) x.add('сообщений: ${v[0]}');
        if (v[1] > 0) x.add('изменённых заметок: ${v[1]}');
        parts.add('«$g» — ${x.join(', ')}');
      });
      notices.clear();
      Notifier.I.notifyNew('Общая папка: новое', parts.join('\n'));
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
    final nothing = all.upTotal + all.downTotal + all.conflicts == 0 && !failed;
    if (nothing) {
      // ничего не изменилось: не перешифровываем и не пишем все файлы заново
      await saveSettings(touch: false);
      if (!auto) await addHistory(rec);
    } else {
      await save();
      await addHistory(rec);
    }
    if (all.up.containsKey('events') || all.down.containsKey('events')) {
      onEventsChanged?.call();
    }
    notifyListeners();
  }

  Future<void> sync() => syncAll();
}

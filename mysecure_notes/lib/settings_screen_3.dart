part of 'settings_screen.dart';

extension _ExtSettingsScreenState2 on _SettingsScreenState {

  Future<void> _upload(List<int>? bytes, {bool savedLocal = false}) async {
    if (!Backup.canUpload(st)) {
      if (mounted) toast(context, 'Укажите сервер для бэкапов (или подключите WebDAV)');
      return;
    }
    final note = ValueNotifier<String>('Загружаю бэкап на сервер…');
    final close = _progress(note);
    try {
      final name = bytes == null
          ? await Backup.createAndUpload(s)
          : await Backup.upload(s, bytes);
      close();
      if (mounted) {
        toast(context, '${savedLocal ? 'Бэкап сохранён. ' : ''}Загружен на сервер: $name');
        setState(() {});
      }
    } catch (e, stk) {
      close();
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Загрузка на сервер не удалась: $e');
    } finally {
      }
  }

  Future<void> _remoteBackups() async {
    if (!Backup.canUpload(st)) {
      toast(context, 'Укажите сервер для бэкапов (или подключите WebDAV)');
      return;
    }
    List<String> names;
    try {
      names = await Backup.listRemote(s);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось получить список: $e');
      return;
    }
    if (!mounted) return;
    if (names.isEmpty) {
      toast(context, 'На сервере бэкапов пока нет');
      return;
    }
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Бэкапы на сервере'),
        children: [
          for (final n in names)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(n),
              onTap: () => Navigator.pop(ctx, n),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final note = ValueNotifier<String>('Скачиваю бэкап…');
    final close = _progress(note);
    List<int>? bytes;
    try {
      bytes = await Backup.downloadRemote(s, pick);
    } catch (e) {
      close();
      if (mounted) toast(context, 'Не удалось скачать: $e');
      return;
    }
    close();
    if (bytes == null) {
      if (mounted) toast(context, 'Файл не найден на сервере');
      return;
    }
    await _restoreBytes(bytes);
  }

  /// Список автоматических копий, сделанных перед сбросом/восстановлением/импортом.
  Future<void> _safetyList() async {
    final l = await Backup.listSafety(s);
    if (!mounted) return;
    final pick = await showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Страховочные копии'),
        children: [
          if (l.isEmpty)
            const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Пока нет. Копия создаётся автоматически перед сбросом, '
                    'восстановлением и импортом из Joplin.')),
          for (final f in l)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f), child: Text(Backup.safetyLabel(f))),
        ],
      ),
    );
    if (pick == null) return;
    await _restoreBytes(await pick.readAsBytes());
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['zip'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    await _restoreBytes(r.files.first.bytes!);
  }

  Future<void> _restoreBytes(List<int> bytes) async {
    if (!Backup.isBackup(bytes)) {
      if (mounted) toast(context, 'Это не бэкап приложения');
      return;
    }
    if (!mounted) return;
    if (!await _ask('Восстановить из бэкапа?',
        'Данные текущего профиля будут заменены. После восстановления войдите с паролем, '
            'под которым делался бэкап.',
        'Восстановить')) {
      return;
    }
    try {
      await Backup.safetyCopy(s, 'restore');
      await Backup.restore(s, bytes);
      await widget.onLogout(false);
    } catch (e, stk) {
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Ошибка восстановления: $e');
    }
  }

  Future<void> _jexImport() async {
    FilePickerResult? r;
    try {
      // любые файлы: Android не знает тип .jex и не даёт выбрать файл с фильтром по расширению
      r = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    } catch (e, stk) {
      AppLog.I.e('jex', '$e', stk);
      if (mounted) toast(context, 'Не удалось открыть выбор файла: $e');
      return;
    }
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final low = f.name.toLowerCase();
    if (!low.endsWith('.jex') && !low.endsWith('.tar')) {
      if (mounted) toast(context, 'Нужен файл экспорта Joplin (.jex), выбран «${f.name}»');
      return;
    }
    List<int>? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      try {
        bytes = await File(f.path!).readAsBytes();
      } catch (e) {
        if (mounted) toast(context, 'Не удалось прочитать файл: $e');
        return;
      }
    }
    if (bytes == null) {
      if (mounted) toast(context, 'Не удалось получить содержимое файла');
      return;
    }
    final note = ValueNotifier<String>('Импорт из Joplin…');
    final close = _progress(note);
    try {
      note.value = 'Страховочная копия…';
      await Backup.safetyCopy(s, 'joplin');
      note.value = 'Импорт из Joplin…';
      final msg = await JexIo.importInto(s, bytes, progress: (t) => note.value = t);
      close();
      if (mounted) toast(context, 'Импорт Joplin: $msg');
    } catch (e, stk) {
      close();
      AppLog.I.e('jex', '$e', stk);
      if (mounted) toast(context, 'Не удалось импортировать JEX: $e');
    } finally {
      }
  }

  Future<void> _pdfExport() async {
    try {
      final bytes = await PdfExport.build(s, s.notes.where((n) => !n.isGroup).toList());
      if (await saveBytes('asrbox_notes.pdf', bytes) && mounted) toast(context, 'PDF сохранён');
    } catch (e, stk) {
      AppLog.I.e('pdf', '$e', stk);
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _mdExport() async {
    try {
      final bytes = await JexIo.exportMarkdown(s, s.notes.where((n) => !n.isGroup).toList());
      if (await saveBytes('asrbox_markdown.zip', bytes) && mounted) {
        toast(context, 'Markdown сохранён');
      }
    } catch (e, stk) {
      AppLog.I.e('md', '$e', stk);
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _jexExport() async {
    try {
      final bytes = await JexIo.exportFrom(s);
      if (await saveBytes('mysecure_notes.jex', bytes) && mounted) {
        toast(context, 'JEX сохранён');
      }
    } catch (e, stk) {
      AppLog.I.e('jex', '$e', stk);
      if (mounted) toast(context, 'Ошибка экспорта: $e');
    }
  }

  Future<void> _icsImport() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final list = Ics.import(utf8.decode(r.files.first.bytes!, allowMalformed: true));
    final have = {
      for (final e in s.events)
        if (!e.deleted) '${e.title}|${e.start}|${e.end}'
    };
    final fresh = list.where((e) => have.add('${e.title}|${e.start}|${e.end}')).toList();
    s.events.addAll(fresh);
    s.eventsChanged();
    if (mounted) {
      toast(context, 'Импортировано событий: ${fresh.length}'
          '${list.length > fresh.length ? ' (повторы пропущены: ${list.length - fresh.length})' : ''}');
    }
  }

  Future<void> _icsExport() async {
    if (await saveBytes('calendar.ics', utf8.encode(Ics.export(s.events))) && mounted) {
      toast(context, 'Файл сохранён');
    }
  }

  /// Все виджеты настроек, разрезанные по заголовкам разделов.
  Map<String, List<Widget>> _sections() {
    final out = <String, List<Widget>>{};
    String? cur;
    for (final w in _allWidgets()) {
      if (w is SectionTitle) {
        cur = w.text;
        out[cur] = [];
      } else if (cur != null) {
        out[cur]!.add(w);
      }
    }
    return out;
  }
}

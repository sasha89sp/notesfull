part of 'backup_page.dart';

extension _ExtBackupPageState1 on _BackupPageState {

  Store get s => widget.store;

  Future<void> _run(String label, Future<String> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      final r = await f();
      if (mounted) setState(() => _status = r);
    } catch (e) {
      if (mounted) setState(() => _status = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _perm(String g) async {
    if (await PhoneData.hasPerms(g)) return true;
    final ok = await PhoneData.requestPerms(g);
    if (!ok && mounted) {
      toast(context, 'Нет разрешения. Его можно выдать в настройках Android → Приложения → ASRbox.');
    }
    return ok;
  }

  String _stamp() {
    final d = DateTime.now();
    String t(int x) => x.toString().padLeft(2, '0');
    return '${d.year}${t(d.month)}${t(d.day)}_${t(d.hour)}${t(d.minute)}';
  }

  /// Сохраняет файл на устройство (и, если выбрано, в облако для бэкапов).
  Future<String> _save(String base, String ext, List<int> plain, int count) async {
    var bytes = plain;
    var e = ext;
    if (_encrypt && s.syncKey != null) {
      bytes = await Crypto.encrypt(s.syncKey!, plain);
      e = '$ext.enc';
    }
    final name = 'asrbox_${base}_${_stamp()}.$e';
    final ok = await saveBytes(name, bytes);
    var msg = ok ? 'Сохранено: $count шт. ($name)' : 'Сохранение отменено';
    if (_toCloud && Backup.canUpload(s.settings)) {
      await Backup.uploadPhone(s, name, bytes);
      msg += '\nЗагружено в облако';
    }
    return msg;
  }

  /// Выбор файла; зашифрованный файл расшифровывается ключом профиля.
  Future<String?> _pick(List<String> exts) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return null;
    var b = r.files.first.bytes;
    if (b == null) {
      final p = r.files.first.path;
      if (p == null) return null;
      b = await File(p).readAsBytes();
    }
    var data = b;
    final head = utf8.decode(data.take(16).toList(), allowMalformed: true).trimLeft();
    final plain = head.startsWith('[') || head.startsWith('{') || head.toUpperCase().startsWith('BEGIN:');
    if (!plain) {
      if (s.syncKey == null) throw 'Файл зашифрован, а ключ профиля недоступен';
      try {
        data = await Crypto.decrypt(s.syncKey!, data);
      } catch (_) {
        throw 'Не удалось расшифровать файл: он создан под другим профилем или пароль не совпал';
      }
    }
    return utf8.decode(data);
  }

  // ---------------------------------------------------------- звонки

  Future<void> _callsExport() => _run('Экспорт звонков', () async {
        if (!await _perm('calls')) return 'Нет разрешения';
        final l = await PhoneData.exportCalls();
        return _save('calls', 'json', utf8.encode(jsonEncode(l)), l.length);
      });

  Future<void> _callsImport() => _run('Импорт звонков', () async {
        if (!await _perm('calls')) return 'Нет разрешения';
        final t = await _pick(['json']);
        if (t == null) return 'Отменено';
        final n = await PhoneData.importCalls(jsonDecode(t) as List<dynamic>);
        return 'Добавлено звонков: $n (повторы пропущены)';
      });

  // ---------------------------------------------------------- контакты

  Future<void> _contactsExport(bool vcf) => _run('Экспорт контактов', () async {
        if (!await _perm('contacts')) return 'Нет разрешения';
        final l = await PhoneData.exportContacts();
        return vcf
            ? _save('contacts', 'vcf', utf8.encode(PhoneData.toVcf(l)), l.length)
            : _save('contacts', 'json', utf8.encode(jsonEncode(l)), l.length);
      });

  Future<void> _contactsImport() => _run('Импорт контактов', () async {
        if (!await _perm('contacts')) return 'Нет разрешения';
        final t = await _pick(['vcf', 'json']);
        if (t == null) return 'Отменено';
        final l = t.trimLeft().startsWith('[')
            ? jsonDecode(t) as List<dynamic>
            : PhoneData.parseVcf(t);
        final n = await PhoneData.importContacts(l);
        return 'Добавлено контактов: $n из ${l.length} (совпадающие пропущены)';
      });

  // ---------------------------------------------------------- SMS

  Future<void> _smsExport() => _run('Экспорт SMS', () async {
        if (!await _perm('sms')) return 'Нет разрешения';
        final l = await PhoneData.exportSms();
        return _save('sms', 'json', utf8.encode(jsonEncode(l)), l.length);
      });

  Future<void> _smsImport() => _run('Импорт SMS', () async {
        final t = await _pick(['json']);
        if (t == null) return 'Отменено';
        final n = await PhoneData.importSms(jsonDecode(t) as List<dynamic>);
        if (n < 0) {
          return 'Android разрешает запись SMS только приложению, выбранному «SMS по умолчанию». '
              'ASRbox не является таким приложением, поэтому восстановить SMS в системное '
              'хранилище нельзя. Файл с сообщениями остаётся доступным для чтения и переноса.';
        }
        return 'Добавлено SMS: $n (повторы пропущены)';
      });

  // ---------------------------------------------------------- Wi-Fi

  Future<void> _wifiExport() => _run('Экспорт Wi-Fi', () async {
        if (!await _perm('wifi')) return 'Нет разрешения';
        final l = await PhoneData.exportWifi();
        if (l.isEmpty) {
          return 'Android не отдаёт список сохранённых сетей приложениям. '
              'Создайте файл вручную (кнопка «Добавить сеть») или подключитесь к сети и повторите.';
        }
        return _save('wifi', 'json', utf8.encode(jsonEncode(l)), l.length);
      });

  Future<void> _wifiImport() => _run('Импорт Wi-Fi', () async {
        final t = await _pick(['json']);
        if (t == null) return 'Отменено';
        final n = await PhoneData.importWifi(jsonDecode(t) as List<dynamic>);
        return 'Передано системе сетей: $n. На Android 10+ подтвердите их в уведомлении/настройках Wi-Fi.';
      });

  Future<void> _wifiAdd() async {
    final ssid = TextEditingController();
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить сеть Wi-Fi'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ssid, decoration: const InputDecoration(labelText: 'Имя сети (SSID)')),
          TextField(controller: pw, decoration: const InputDecoration(labelText: 'Пароль')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить в файл')),
        ],
      ),
    );
    final name = ssid.text.trim();
    final pass = pw.text;
    ssid.dispose();
    pw.dispose();
    if (ok != true || name.isEmpty) return;
    await _run('Сохранение', () async {
      final l = [
        {'ssid': name, 'password': pass, 'security': pass.isEmpty ? 'open' : 'wpa'}
      ];
      return _save('wifi', 'json', utf8.encode(jsonEncode(l)), 1);
    });
  }

  // ---------------------------------------------------------- бэкап телефона одной кнопкой

  Future<void> _phoneAll() => _run('Бэкап телефона', () async {
        final r = await PhoneData.runAll(s, ask: true);
        if (r.uploaded) return 'Готово и загружено в облако: ${r.info}';
        final ok = await saveBytes(r.name, r.bytes);
        return '${ok ? 'Сохранено в файл' : 'Сохранение отменено'} (облако не настроено): ${r.info}';
      });

  /// Восстановление из архива телефона одной кнопкой: выбрать файл (.zip или .zip.enc)
  /// и вернуть контакты, звонки, SMS, Wi-Fi.
  Future<void> _phoneRestore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final List<int>? bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    await _run('Восстановление телефона', () => PhoneData.restoreArchive(s, bytes));
  }

  Widget _sectionHead(String title, String sub, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
            ]),
          ),
        ]),
      );

  // ---------------------------------------------------------- полный бэкап

  Future<void> _fullToFile() => _run('Создание бэкапа', () async {
        final List<int> b = await Backup.create(s);
        final name = 'asrbox_full_${_stamp()}.zip';
        final ok = await saveBytes(name, b);
        return ok ? 'Сохранено: $name' : 'Сохранение отменено';
      });

  Future<void> _fullToCloud() => _run('Загрузка бэкапа', () async {
        if (!Backup.canUpload(s.settings)) {
          return 'Сервер для бэкапов не настроен: Настройки → Резервные копии';
        }
        final n = await Backup.createAndUpload(s);
        return 'Загружено: $n';
      });

  Widget _card(String title, IconData icon, String hint, List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ]),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(hint, style: TextStyle(fontSize: 12, color: Pal.secondary(context))),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ]),
        ),
      ),
    );
  }
}

extension _ExtBackupPageState2 on _BackupPageState {

  Widget _btn(String t, IconData i, VoidCallback f, {bool filled = false}) {
    final cb = _busy ? null : f;
    return filled
        ? FilledButton.icon(onPressed: cb, icon: Icon(i, size: 18), label: Text(t))
        : OutlinedButton.icon(onPressed: cb, icon: Icon(i, size: 18), label: Text(t));
  }
}

// ▸ Часть settings_screen.dart: Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт)  [содержит: _ExtSettingsScreenState1]
part of 'settings_screen.dart';

extension _ExtSettingsScreenState1 on _SettingsScreenState {

  Store get s => widget.store;

  void _apply() {
    st.author = c['author']!.text.trim();
    st.url = c['url']!.text.trim();
    st.user = c['user']!.text.trim();
    st.pass = c['pass']!.text;
    st.txUrl = c['txUrl']!.text.trim();
    st.txKey = c['txKey']!.text.trim();
    st.txModel = c['txModel']!.text.trim();
    st.gClientId = c['gId']!.text.trim();
    st.gSecret = c['gSecret']!.text.trim();
    st.bkUrl = c['bkUrl']!.text.trim();
    st.bkUser = c['bkUser']!.text.trim();
    st.bkPass = c['bkPass']!.text;
    st.bkFolder = c['bkFolder']!.text.trim();
    final l = int.tryParse(c['lock']!.text.trim()) ?? 90;
    st.autoLock = l.clamp(15, 3600).toInt();
  }

  /// Кнопка «Сохранить»: записывает только настройки, без синхронизации.
  Future<void> _saveOnly() async {
    _autoTimer?.cancel();
    final oldName = st.author;
    _apply();
    await s.saveSettings();
    if (st.author != oldName) await s.renameCurrent(st.author);
    if (mounted) toast(context, 'Настройки сохранены');
  }

  /// Сброс профиля: предупреждение и подтверждение словом.
  Future<void> _reset() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Сбросить профиль?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Все данные профиля будут удалены с этого устройства без возможности '
                'восстановления, кроме копии в облаке и резервных копий. Для подтверждения введите СБРОС.'),
            const SizedBox(height: 10),
            TextField(controller: ctl, onChanged: (_) => set(() {})),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            TextButton(
                onPressed:
                    ctl.text.trim().toUpperCase() == 'СБРОС' ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Сбросить')),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (ok != true) return;
    _autoTimer?.cancel();
    final sp = await Backup.safetyCopy(s, 'reset');
    if (mounted) toast(context, sp == null ? 'Страховочная копия не создана' : 'Страховочная копия сохранена');
    await s.resetProfile();
    await widget.onLogout(true);
  }

  /// Настройки сохраняются сами; кнопка «Сохранить» делает это сразу.
  void _auto() {
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(milliseconds: 700), _autoNow);
  }

  void _navFix() {
    s.refresh();
    _auto();
  }

  Future<void> _autoNow() async {
    final oldName = st.author;
    _apply();
    await s.saveSettings();
    if (st.author != oldName) await s.renameCurrent(st.author);
    final sig = '${st.url}|${st.user}|${st.pass}';
    final changed = sig != _syncSig;
    _syncSig = sig;
    s.refresh();
    // ввели или изменили данные WebDAV: синхронизация запускается автоматически
    if (changed && st.syncConfigured) s.syncAll();
  }

  Widget _field(String key, String label,
      {bool obscure = false, String? hint, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c[key],
        obscureText: obscure,
        keyboardType: type,
        onChanged: (_) => _auto(),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _drop(String label, String value, Map<String, String> opts,
      void Function(String) set) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(flex: 5, child: Text(label)),
        const SizedBox(width: 8),
        // выпадающий список ограничен по ширине: длинные подписи не вылезают за экран телефона
        Expanded(
          flex: 6,
          child: DropdownButton<String>(
          isExpanded: true,
          value: opts.containsKey(value) ? value : opts.keys.first,
          items: [
            for (final o in opts.entries)
              DropdownMenuItem(value: o.key, child: Text(o.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => set(v));
              _auto();
            }
          },
        ),
        ),
      ]),
    );
  }

  Future<void> _google() async {
    _apply();
    setState(() => gStatus = 'Откроется браузер для входа в Google…');
    try {
      await GoogleCal.authorize(s);
      if (mounted) setState(() => gStatus = 'Подключено');
      s.syncAll();
    } catch (e) {
      setState(() => gStatus = '$e');
    }
  }

  Future<void> _bio(bool on) async {
    if (on) {
      final ok = await s.enableBiometric();
      if (!ok && mounted) toast(context, 'Не удалось включить биометрию');
    } else {
      await s.disableBiometric();
    }
    if (mounted) setState(() {});
  }

  Future<bool> _ask(String title, String text, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _davLogout() async {
    if (!await _ask('Выйти из WebDAV?',
        'Приложение отключится от облака. Локальные данные останутся на устройстве.', 'Выйти')) {
      return;
    }
    s.cancelSync();
    st.user = '';
    st.pass = '';
    c['user']!.text = '';
    c['pass']!.text = '';
    _syncSig = '${st.url}||';
    await s.saveSettings();
    s.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _googleLogout() async {
    if (!await _ask('Выйти из Google Календаря?',
        'Аккаунт будет отключён. Локальные события останутся.', 'Выйти')) {
      return;
    }
    await GoogleCal.disconnect(s);
    if (mounted) setState(() => gStatus = 'Отключено');
  }

  /// Окно с ходом долгой операции. Возвращает функцию «закрыть».
  VoidCallback _progress(ValueNotifier<String> text) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: text,
                builder: (_, v, __) => Text(v),
              ),
            ),
          ]),
        ),
      ),
    );
    return () {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    };
  }

  Future<void> _backup() async {
    _apply();
    final note = ValueNotifier<String>('Создаю бэкап…');
    final close = _progress(note);
    List<int> bytes;
    try {
      bytes = await Backup.create(s);
    } catch (e, stk) {
      close();
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Ошибка бэкапа: $e');
      return;
    }
    close();
    final d = DateTime.now();
    final name = 'asrbox_backup_${d.year}${two(d.month)}${two(d.day)}.zip';
    var saved = false;
    try {
      saved = await saveBytes(name, bytes);
    } catch (e, stk) {
      AppLog.I.e('backup', '$e', stk);
      if (mounted) toast(context, 'Не удалось сохранить файл: $e');
    }
    // галочка включена — загрузка на сервер идёт сама, без вопросов
    if (st.bkAuto) {
      await _upload(bytes, savedLocal: saved);
    } else if (saved && mounted) {
      toast(context, 'Бэкап сохранён');
    }
  }
}

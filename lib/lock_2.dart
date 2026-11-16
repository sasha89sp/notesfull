// ▸ Часть lock.dart: Экран входа, создание профиля, пароль, биометрия  [содержит: _ExtLockScreenState1]
part of 'lock.dart';

extension _ExtLockScreenState1 on _LockScreenState {

  Store get s => widget.store;
  bool get _has => s.profiles.isNotEmpty;

  Future<void> _selectId(String id, {bool autoBio = false}) async {
    final p = s.profileById(id);
    if (p == null) return;
    s.selectProfile(id);
    _selId = id;
    if (p.name.isNotEmpty) _login.text = p.name;
    final rp = await s.rememberedPw(id);
    final has = await s.bioStored();
    if (!mounted) return;
    setState(() {
      _bio = has;
      _remember = rp != null;
      _pw.text = rp ?? '';
    });
    if (autoBio && has && rp == null) _tryBio();
  }

  void _onLoginChanged(String v) {
    final p = s.profileByName(v);
    if (p != null && p.id != _selId) _selectId(p.id);
  }

  Future<void> _tryBio() async {
    final ok = await s.unlockBio();
    if (ok) {
      _finish();
    } else if (mounted) {
      setState(() => _err = 'Биометрия не подтверждена');
    }
  }

  Future<void> _finish() async {
    if (_remember && _pw.text.isNotEmpty) {
      await s.rememberLogin(_pw.text);
    } else {
      await s.forgetLogin();
    }
    s.wantPicker = false;
    widget.onDone();
  }

  void _fail(String m) {
    if (mounted) {
      setState(() {
        _busy = false;
        _err = m;
      });
    }
  }

  // --------------------------------------------------------------- вход

  Future<void> _submit() async {
    final name = _login.text.trim();
    final pw = _pw.text;
    ProfileInfo? p = s.profileByName(name);
    p ??= s.profiles.length == 1 && (s.profiles.first.name.isEmpty || name.isEmpty)
        ? s.profiles.first
        : null;
    if (p == null) {
      _fail(name.isEmpty
          ? 'Введите логин'
          : 'Профиль «$name» не найден. Создайте новый или подключите существующий');
      return;
    }
    if (pw.isEmpty) {
      _fail('Введите пароль');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      s.selectProfile(p.id);
      final ok = await s.unlock(pw);
      if (!ok) {
        _fail('Неверный пароль');
        return;
      }
      if (p.name.isEmpty) {
        // профиль из прошлой версии получает логин
        final nm = s.settings.author.isNotEmpty ? s.settings.author : name;
        if (s.settings.author.isEmpty && nm.isNotEmpty) {
          s.settings.author = nm;
          await s.saveSettings();
        }
        await s.renameCurrent(nm);
      }
      await _finish();
    } catch (e) {
      _fail('Ошибка: $e');
    }
  }

  // --------------------------------------------------------------- создание

  bool _validNew() {
    final name = _login.text.trim();
    if (name.isEmpty) {
      _fail('Введите логин: это имя вашего профиля');
      return false;
    }
    if (s.profileByName(name) != null) {
      _fail('Профиль «$name» уже есть на устройстве. Нажмите «Войти»');
      return false;
    }
    if (_pw.text.length < 8) {
      _fail('Пароль: минимум 8 символов');
      return false;
    }
    return true;
  }

  Future<bool> _repeatPassword() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Повторите пароль'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Пароль нельзя восстановить: если забудете, данные будут потеряны.'),
          const SizedBox(height: 12),
          TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Пароль ещё раз')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text == _pw.text),
              child: const Text('Создать')),
        ],
      ),
    );
    c.dispose();
    if (ok == false && mounted) {
      // отличить отмену от несовпадения нельзя: показываем подсказку один раз
      setState(() => _err = 'Пароли не совпали или создание отменено');
    }
    return ok == true;
  }

  Future<void> _createLocal() async {
    setState(() => _err = null);
    if (!_validNew()) return;
    if (!await _repeatPassword()) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await s.createProfile(_login.text.trim(), _pw.text);
      await _finish();
    } catch (e) {
      _fail('Ошибка: $e');
    }
  }

  Future<void> _connect() async {
    setState(() => _err = null);
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ConnectScreen(store: s)),
    );
    if (ok == true) {
      _remember = false; // запоминание выбрано на экране подключения
      widget.onDone();
    }
  }

  Future<void> _pickProfile() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Профили на устройстве'),
        children: [
          for (final p in s.profiles)
            ListTile(
              leading: Icon(p.kind == 'online' ? Icons.cloud_outlined : Icons.phone_android),
              title: Text(p.name.isEmpty ? 'Профиль' : p.name),
              subtitle: Text(p.kind == 'online' ? 'онлайн' : 'локальный'),
              selected: p.id == _selId,
              onTap: () => Navigator.pop(ctx, p.id),
            ),
        ],
      ),
    );
    if (id != null) {
      _pw.clear();
      await _selectId(id);
    }
  }
}

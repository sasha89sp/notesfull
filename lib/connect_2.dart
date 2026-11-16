// ▸ Часть connect.dart: Экран подключения хранилища и аккаунта ASRbox (двухуровневая авторизация)  [содержит: _ExtConnectScreenState1]
part of 'connect.dart';

extension _ExtConnectScreenState1 on _ConnectScreenState { // webdav | gdrive | local
  bool get _local => _kind == 'local';
  bool get _gd => _kind == 'gdrive';

  Store get s => widget.store;

  void _fail(String m) {
    if (mounted) {
      setState(() {
        _busy = false;
        _err = m;
      });
    }
  }

  String get _folder {
    final f = (_picked ?? _newFolder.text).trim();
    return f.startsWith('/') ? f : '/$f';
  }

  // -------------------------------------------------------------- шаг 1

  Future<void> _pickDir() async {
    final p = await FilePicker.platform.getDirectoryPath();
    if (p != null) setState(() => _path.text = p);
  }

  Future<void> _toFolders() async {
    setState(() {
      _err = null;
      _busy = true;
    });
    try {
      if (_local) {
        final p = _path.text.trim();
        if (p.isEmpty || !await Directory(p).exists()) {
          _fail('Папка не найдена. Выберите существующую папку');
          return;
        }
        _remote = LocalRemote(p);
      } else if (_gd) {
        if (_gdToken.isEmpty) {
          _fail('Сначала войдите в Google');
          return;
        }
        _remote = GDriveRemote(Settings(gClientId: _gId.text.trim(), gSecret: _gSecret.text.trim(), gdRefresh: _gdToken));
      } else {
        if (_url.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty) {
          _fail('Заполните адрес, логин и пароль WebDAV');
          return;
        }
        _remote = Dav(_url.text.trim(), _user.text.trim(), _pass.text);
      }
      _dirs = await Accounts.folders(_remote!, '/');
      _dirs.removeWhere((e) => e.startsWith('.') || e == 'Trash');
      _picked = _dirs.contains('ASRbox') ? 'ASRbox' : null;
      if (mounted) {
        setState(() {
          _busy = false;
          _step = 1;
        });
      }
    } catch (e) {
      _fail('Не удалось подключиться: $e');
    }
  }

  // -------------------------------------------------------------- шаг 2

  Future<void> _toAccount() async {
    final f = _folder;
    if (f == '/' || f.trim().length < 2) {
      _fail('Выберите папку или введите имя новой');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final sub = await _remote!.listDirs(f);
      _legacyAvail = sub.contains('personal') && !sub.contains('accounts');
      _legacy = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _askRepeat = false;
          _step = 2;
        });
      }
    } catch (e) {
      _fail('Не удалось прочитать папку: $e');
    }
  }

  // -------------------------------------------------------------- шаг 3

  Future<void> _enter() async {
    final login = _login.text.trim();
    final pw = _pw.text;
    if (login.isEmpty) return _fail('Введите логин');
    if (pw.length < 8) return _fail('Пароль: минимум 8 символов');
    setState(() {
      _busy = true;
      _err = null;
    });
    final r = _remote!;
    final f = _folder;
    try {
      if (_legacy) {
        final v = await SyncService.verifyLegacy(r, f, pw);
        if (v == 'wrong') return _fail('Пароль не подходит к данным в этой папке');
        if (v.startsWith('error:')) return _fail('Ошибка: ${v.substring(6)}');
        await _make(login, pw, '', null);
        return;
      }
      final v = await Accounts.verify(r, f, login, pw);
      if (v.startsWith('error:')) return _fail('Нет связи с хранилищем: ${v.substring(6)}');
      if (v == 'wrong') return _fail('Неверный пароль для этого логина');
      if (v == 'nouser') {
        if (!_askRepeat) {
          setState(() {
            _busy = false;
            _askRepeat = true;
            _err = 'Такого аккаунта в этой папке нет. Повторите пароль и нажмите «Создать аккаунт». '
                'Пароль восстановить нельзя.';
          });
          return;
        }
        if (_pw2.text != pw) return _fail('Пароли не совпали');
        final uid = await Accounts.register(r, f, login, pw, login);
        await _make(login, pw, uid, null);
        return;
      }
      // вход в существующий аккаунт: подтягиваем его настройки
      final uid = await Accounts.uidFor(login);
      final key = await Accounts.syncKey(pw, uid);
      final remoteSettings = await Accounts.pullSettings(r, '$f/users/$uid', key);
      await _make(login, pw, uid, remoteSettings);
    } catch (e) {
      if (e == 'exists') return _fail('Этот логин уже занят');
      AppLog.I.e('connect', '$e');
      _fail('Ошибка: $e');
    }
  }

  Future<void> _make(String login, String pw, String uid, Map<String, dynamic>? rs) async {
    if (s.profiles.any((p) => p.uid == uid && uid.isNotEmpty && p.name == login)) {
      return _fail('Профиль «$login» уже есть на устройстве. Войдите в него на главном экране');
    }
    await s.createProfile(
      login,
      pw,
      kind: 'online',
      url: _local || _gd ? '' : _url.text.trim(),
      user: _local || _gd ? '' : _user.text.trim(),
      pass: _local || _gd ? '' : _pass.text,
      storage: _kind,
      folder: _folder,
      localPath: _local ? _path.text.trim() : '',
      uid: uid,
      remoteSettings: rs,
    );
    if (_gd) {
      s.settings.gClientId = _gId.text.trim();
      s.settings.gSecret = _gSecret.text.trim();
      s.settings.gdRefresh = _gdToken;
      await s.saveSettings();
    }
    if (_remember) await s.rememberLogin(pw);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _googleLogin() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final t = await GDrive.authorizeRaw(_gId.text.trim(), _gSecret.text.trim());
      if (mounted) {
        setState(() {
          _gdToken = t;
          _busy = false;
        });
      }
    } catch (e) {
      _fail('$e');
    }
  }

  void _preset(String url) => setState(() => _url.text = url);

  List<Widget> _stepStorage(Color sec) => [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'webdav', label: Text('WebDAV'), icon: Icon(Icons.cloud_outlined)),
            ButtonSegment(value: 'gdrive', label: Text('Google'), icon: Icon(Icons.add_to_drive_outlined)),
            ButtonSegment(value: 'local', label: Text('Папка'), icon: Icon(Icons.folder_outlined)),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: 16),
        if (_kind == 'webdav') ...[
          Text(
              'WebDAV: Mail.ru Облако, Яндекс Диск и любой другой сервер. Нужен пароль для '
              'внешнего приложения (не основной пароль аккаунта). Ваш собственный логин и пароль '
              'ASRbox — на третьем шаге.',
              style: TextStyle(color: sec, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ActionChip(label: const Text('Mail.ru'), onPressed: () => _preset('https://webdav.cloud.mail.ru')),
            ActionChip(label: const Text('Яндекс Диск'), onPressed: () => _preset('https://webdav.yandex.ru')),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _url, decoration: const InputDecoration(labelText: 'Адрес WebDAV')),
          const SizedBox(height: 10),
          TextField(controller: _user, decoration: const InputDecoration(labelText: 'Логин облака (почта)')),
          const SizedBox(height: 10),
          TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль приложения')),
        ] else if (_gd) ...[
          Text(
              'Google Диск через Drive API. Приложение видит только созданные им папки. '
              'Нужны Client ID и Client Secret (тип «Приложение для ПК», включите Google Drive API в консоли Google Cloud).',
              style: TextStyle(color: sec, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: _gId, decoration: const InputDecoration(labelText: 'Client ID')),
          const SizedBox(height: 10),
          TextField(
              controller: _gSecret,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Client Secret')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _googleLogin,
            icon: Icon(_gdToken.isEmpty ? Icons.login : Icons.check_circle_outline),
            label: Text(_gdToken.isEmpty ? 'Войти в Google' : 'Вход выполнен'),
          ),
        ] else ...[
          Text(
              'Данные лягут в обычную папку на устройстве. Её можно синхронизировать '
              'другой программой (например, клиентом облака или Syncthing).',
              style: TextStyle(color: sec, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _path,
            decoration: InputDecoration(
              labelText: 'Путь к папке',
              suffixIcon: IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickDir),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _toFolders, child: const Text('Далее')),
      ];
}

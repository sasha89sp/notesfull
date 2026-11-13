import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'accounts.dart';
import 'applog.dart';
import 'gdrive.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';
import 'sync.dart';
import 'widgets.dart';

/// Двухуровневая авторизация ASRbox:
/// 1) хранилище (WebDAV или папка на устройстве) → 2) папка на нём →
/// 3) собственный логин и пароль в приложении.
/// На одном WebDAV может жить сколько угодно аккаунтов: данные каждого лежат в
/// своей папке и зашифрованы его паролем.
class ConnectScreen extends StatefulWidget {
  final Store store;
  const ConnectScreen({super.key, required this.store});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  int _step = 0;
  String _kind = 'webdav'; // webdav | gdrive | local
  bool get _local => _kind == 'local';
  bool get _gd => _kind == 'gdrive';
  final _gId = TextEditingController();
  final _gSecret = TextEditingController();
  String _gdToken = '';
  final _url = TextEditingController(text: 'https://webdav.cloud.mail.ru');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _path = TextEditingController();
  final _newFolder = TextEditingController(text: 'ASRbox');
  final _login = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  Remote? _remote;
  List<String> _dirs = [];
  String? _picked; // выбранная существующая папка
  bool _legacy = false;
  bool _legacyAvail = false;
  bool _askRepeat = false;
  bool _remember = true;
  bool _busy = false;
  String? _err;

  Store get s => widget.store;

  @override
  void dispose() {
    for (final c in [_url, _user, _pass, _path, _newFolder, _login, _pw, _pw2, _gId, _gSecret]) {
      c.dispose();
    }
    super.dispose();
  }

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

  // -------------------------------------------------------------- вид

  @override
  Widget build(BuildContext context) {
    final sec = Pal.secondary(context);
    final titles = ['Хранилище', 'Папка', 'Ваш аккаунт'];
    return Scaffold(
      appBar: AppBar(title: Text('Подключение · ${titles[_step]}')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Шаг ${_step + 1} из 3',
                    textAlign: TextAlign.center, style: TextStyle(color: sec, fontSize: 12)),
                const SizedBox(height: 16),
                if (_step == 0) ..._stepStorage(sec),
                if (_step == 1) ..._stepFolder(sec),
                if (_step == 2) ..._stepAccount(sec),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: Pal.error(context))),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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

  List<Widget> _stepFolder(Color sec) => [
        Text('Выберите папку с данными ASRbox или создайте новую.',
            style: TextStyle(color: sec, fontSize: 13)),
        const SizedBox(height: 8),
        if (_dirs.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in _dirs)
                  ListTile(
                    dense: true,
                    leading: Icon(_picked == d ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: Text(d),
                    onTap: () => setState(() => _picked = d),
                  ),
              ],
            ),
          ),
        ListTile(
          dense: true,
          leading: Icon(_picked == null ? Icons.radio_button_checked : Icons.radio_button_off),
          title: const Text('Новая папка'),
          onTap: () => setState(() => _picked = null),
        ),
        if (_picked == null)
          TextField(
              controller: _newFolder,
              decoration: const InputDecoration(labelText: 'Название новой папки')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step = 0),
                  child: const Text('Назад'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : _toAccount, child: const Text('Далее'))),
        ]),
      ];

  List<Widget> _stepAccount(Color sec) => [
        Text(
            'Придумайте логин и пароль ASRbox или войдите с уже существующими. '
            'Данные каждого пользователя шифруются его паролем и недоступны остальным, '
            'даже если все используют один WebDAV. Пароль восстановить нельзя.',
            style: TextStyle(color: sec, fontSize: 13)),
        const SizedBox(height: 12),
        if (_legacyAvail)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Данные старой версии'),
            subtitle: const Text('В папке есть профиль без аккаунтов (MySecureApp)',
                style: TextStyle(fontSize: 12)),
            value: _legacy,
            onChanged: (v) => setState(() => _legacy = v),
          ),
        TextField(controller: _login, decoration: const InputDecoration(labelText: 'Логин')),
        const SizedBox(height: 10),
        TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Пароль (от 8 символов)')),
        if (_askRepeat) ...[
          const SizedBox(height: 10),
          TextField(
              controller: _pw2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Повторите пароль')),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text('Запомнить на этом устройстве'),
          value: _remember,
          onChanged: (v) => setState(() => _remember = v ?? false),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _step = 1),
                  child: const Text('Назад'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : _enter,
                  child: Text(_askRepeat ? 'Создать аккаунт' : 'Войти'))),
        ]),
      ];
}

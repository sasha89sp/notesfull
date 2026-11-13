import 'package:flutter/material.dart';
import 'connect.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

/// Экран входа. Если профиль на устройстве уже есть, вход идёт в него.
/// Создание нового профиля — отдельные кнопки ниже. Логин, пароль и «Запомнить»
/// используются всеми действиями.
class LockScreen extends StatefulWidget {
  final Store store;
  final bool exists;
  final VoidCallback onDone;

  const LockScreen({
    super.key,
    required this.store,
    required this.exists,
    required this.onDone,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _login = TextEditingController();
  final _pw = TextEditingController();
  String? _err;
  bool _busy = false;
  bool _bio = false;
  bool _remember = false;
  String _selId = '';

  Store get s => widget.store;
  bool get _has => s.profiles.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_has) {
      _selectId(s.curId, autoBio: !s.wantPicker);
      if (s.wantPicker) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pickProfile();
        });
      }
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _pw.dispose();
    super.dispose();
  }

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

  // --------------------------------------------------------------- вид

  @override
  Widget build(BuildContext context) {
    final sec = Pal.secondary(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon/icon_512.png', width: 72, height: 72),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _has ? 'ASRbox' : 'Добро пожаловать в ASRbox',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _has
                      ? 'Введите логин и пароль профиля.'
                      : 'Введите логин и пароль, затем выберите действие. '
                          'Все данные шифруются AES-256; пароль восстановить нельзя.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sec, fontSize: 13),
                ),
                if (_bio) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _tryBio,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Войти по биометрии'),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: _login,
                  autofocus: !_bio,
                  onChanged: _onLoginChanged,
                  decoration: const InputDecoration(labelText: 'Логин'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  onSubmitted: (_) => _has ? _submit() : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Запомнить'),
                  subtitle: const Text('Не вводить данные входа каждый раз',
                      style: TextStyle(fontSize: 12)),
                  value: _remember,
                  onChanged: (v) => setState(() => _remember = v ?? false),
                ),
                if (_err != null) ...[
                  const SizedBox(height: 4),
                  Text(_err!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Pal.error(context))),
                ],
                const SizedBox(height: 12),
                if (_has)
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Войти'),
                  ),
                if (_busy && !_has)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2))),
                const SizedBox(height: 16),
                Text(_has ? 'Другие действия' : 'Выберите действие',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sec, fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _createLocal,
                  child: const Text('Создать новый локальный профиль'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('Подключить хранилище (WebDAV / папка)'),
                ),
                if (s.profiles.length > 1)
                  TextButton(
                    onPressed: _busy ? null : _pickProfile,
                    child: const Text('Сменить профиль'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'connect.dart';
import 'store.dart';
import 'util.dart';
import 'widgets.dart';

part 'lock_2.dart';


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
  }}
import 'package:flutter/material.dart';
import 'store.dart';
import 'widgets.dart';

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
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _err;
  bool _busy = false;
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    if (widget.exists) _initBio();
  }

  Future<void> _initBio() async {
    final has = await widget.store.bioStored();
    if (!mounted) return;
    setState(() => _bio = has);
    if (has) _tryBio();
  }

  Future<void> _tryBio() async {
    final ok = await widget.store.unlockBio();
    if (ok) {
      widget.onDone();
    } else if (mounted) {
      setState(() => _err = 'Биометрия не подтверждена');
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _pw.text;
    if (!widget.exists) {
      if (p.length < 8) {
        setState(() => _err = 'Минимум 8 символов');
        return;
      }
      if (p != _pw2.text) {
        setState(() => _err = 'Пароли не совпадают');
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      if (widget.exists) {
        final ok = await widget.store.unlock(p);
        if (!ok) {
          setState(() {
            _busy = false;
            _err = 'Неверный пароль';
          });
          return;
        }
      } else {
        await widget.store.create(p);
      }
      widget.onDone();
    } catch (e) {
      setState(() {
        _busy = false;
        _err = 'Ошибка: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = !widget.exists;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  creating ? 'Создайте мастер-пароль' : 'Введите пароль',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                if (creating) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Все данные шифруются AES-256. Пароль нельзя восстановить: '
                    'если забудете, данные будут потеряны. На втором устройстве '
                    'используйте тот же пароль — тогда личные данные синхронизируются.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Pal.secondary(context), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  autofocus: !_bio,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  onSubmitted: (_) => creating ? null : _submit(),
                ),
                if (creating) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw2,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Повторите пароль'),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Pal.error(context))),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(creating ? 'Создать' : 'Войти'),
                ),
                if (_bio) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _tryBio,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Войти по биометрии'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

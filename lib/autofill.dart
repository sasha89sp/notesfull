import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';
import 'pass_store.dart';
import 'util.dart';
import 'widgets.dart';

/// Запрос автозаполнения от Android (приходит, когда приложение открыто
/// сервисом автозаполнения, а не пользователем).
class AutofillRequest {
  final String pkg;
  final String domain;
  AutofillRequest(this.pkg, this.domain);
}

Future<AutofillRequest?> autofillRequest() async {
  if (!Platform.isAndroid) return null;
  try {
    final r = await nativeChannel
        .invokeMethod<Map<dynamic, dynamic>>('autofillRequest');
    if (r == null) return null;
    return AutofillRequest(
        (r['pkg'] ?? '').toString(), (r['domain'] ?? '').toString());
  } catch (_) {
    return null;
  }
}

/// true только в сборке «autofill» (там есть нативный сервис).
Future<bool> autofillSupported() async {
  if (!Platform.isAndroid) return false;
  try {
    return (await nativeChannel.invokeMethod<bool>('autofillSupported')) ??
        false;
  } catch (_) {
    return false;
  }
}

class AutofillPicker extends StatefulWidget {
  final PassStore pass;
  final AutofillRequest request;
  const AutofillPicker({super.key, required this.pass, required this.request});
  @override
  State<AutofillPicker> createState() => _AutofillPickerState();
}

class _AutofillPickerState extends State<AutofillPicker> {
  final _pw = TextEditingController();
  final _q = TextEditingController();
  String? _err;
  bool _busy = false;
  String _search = '';

  PassStore get p => widget.pass;

  @override
  void initState() {
    super.initState();
    setSecure(true);
  }

  @override
  void dispose() {
    _pw.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    try {
      await nativeChannel.invokeMethod<void>('autofillCancel');
    } catch (_) {}
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ok = await p.unlock(_pw.text);
      if (!ok) _err = 'Неверный пароль';
    } catch (e) {
      _err = 'Ошибка: $e';
    }
    _pw.clear();
    if (mounted) setState(() => _busy = false);
  }

  int _score(PassEntry e) {
    final d = widget.request.domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final pk = widget.request.pkg.toLowerCase();
    final url = e.url.toLowerCase();
    final t = e.title.toLowerCase();
    var sc = 0;
    if (d.isNotEmpty && (url.contains(d) || t.contains(d))) sc += 10;
    const skip = {'com', 'org', 'net', 'android', 'app', 'ru', 'www', 'mobile'};
    for (final part in pk.split('.')) {
      if (part.length > 2 && !skip.contains(part)) {
        if (url.contains(part) || t.contains(part)) sc += 5;
      }
    }
    return sc;
  }

  Future<void> _pick(PassEntry e) async {
    try {
      await nativeChannel.invokeMethod<void>(
          'autofillResult', {'username': e.username, 'password': e.password});
    } catch (_) {}
  }

  Widget _body() {
    if (!p.exists) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Хранилище паролей ещё не создано. Откройте приложение и создайте его во вкладке «Пароли».',
            textAlign: TextAlign.center),
      ));
    }
    if (!p.unlocked) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.key, size: 48),
                const SizedBox(height: 12),
                const Text('Пароль от хранилища паролей',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  onSubmitted: (_) => _unlock(),
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_err!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Pal.error(context))),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: const Text('Открыть')),
              ],
            ),
          ),
        ),
      );
    }
    var list = p.visible;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      final d = _score(b) - _score(a);
      return d != 0 ? d : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _q,
          decoration: const InputDecoration(
              hintText: 'Поиск', prefixIcon: Icon(Icons.search), isDense: true),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const Center(child: Text('Записей нет'))
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final e in list)
                    AppCard(
                      onTap: () => _pick(e),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Avatar(e.title, 0xFF5856D6),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.title.isEmpty ? 'Без названия' : e.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(e.username,
                                    style: TextStyle(
                                        color: Pal.secondary(context),
                                        fontSize: 13)),
                              ]),
                        ),
                        if (_score(e) > 0)
                          Icon(Icons.check_circle,
                              size: 18, color: Pal.success(context)),
                      ]),
                    ),
                ],
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final who = widget.request.domain.isNotEmpty
        ? widget.request.domain
        : widget.request.pkg;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
        title: Text(who.isEmpty ? 'Автозаполнение' : who,
            style: const TextStyle(fontSize: 18)),
      ),
      body: AnimatedBuilder(animation: p, builder: (_, __) => _body()),
    );
  }
}

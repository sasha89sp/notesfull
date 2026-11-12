import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'pass_io.dart';
import 'pass_store.dart';
import 'store.dart';
import 'totp.dart';
import 'util.dart';
import 'widgets.dart';

String generatePassword(
    {int length = 20,
    bool upper = true,
    bool lower = true,
    bool digits = true,
    bool symbols = true}) {
  const u = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const l = 'abcdefghijkmnopqrstuvwxyz';
  const d = '23456789';
  const s = '!@#\$%^&*()-_=+[]{};:,.?';
  final pools = <String>[
    if (upper) u,
    if (lower) l,
    if (digits) d,
    if (symbols) s,
  ];
  if (pools.isEmpty) pools.add(l);
  final r = Random.secure();
  final chars = <String>[];
  for (final p in pools) {
    chars.add(p[r.nextInt(p.length)]);
  }
  final all = pools.join();
  while (chars.length < length) {
    chars.add(all[r.nextInt(all.length)]);
  }
  chars.shuffle(r);
  return chars.take(length).join();
}

Future<String?> showGenerator(BuildContext context) {
  var len = 20.0;
  var up = true, lo = true, di = true, sy = true;
  var pw = generatePassword();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        void regen() => set(() => pw = generatePassword(
            length: len.round(), upper: up, lower: lo, digits: di, symbols: sy));
        return AlertDialog(
          title: const Text('Генератор паролей'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SelectableText(pw,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
              Row(children: [
                Text('Длина ${len.round()}'),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 64,
                    value: len,
                    onChanged: (v) {
                      len = v;
                      regen();
                    },
                  ),
                ),
              ]),
              CheckboxListTile(
                  dense: true,
                  title: const Text('A–Z'),
                  value: up,
                  onChanged: (v) {
                    up = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('a–z'),
                  value: lo,
                  onChanged: (v) {
                    lo = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('0–9'),
                  value: di,
                  onChanged: (v) {
                    di = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('Символы'),
                  value: sy,
                  onChanged: (v) {
                    sy = v ?? true;
                    regen();
                  }),
            ]),
          ),
          actions: [
            TextButton(onPressed: regen, child: const Text('Ещё')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, pw),
                child: const Text('Использовать')),
          ],
        );
      },
    ),
  );
}

// =============================================================== страница

class PassPage extends StatefulWidget {
  final Store store;
  final PassStore pass;
  const PassPage({super.key, required this.store, required this.pass});
  @override
  State<PassPage> createState() => _PassPageState();
}

class _PassPageState extends State<PassPage> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _search = TextEditingController();
  String? _err;
  bool _busy = false;
  String _folder = '\u0000all'; // \u0000all | \u0000fav | имя папки
  String _q = '';

  PassStore get p => widget.pass;

  @override
  void initState() {
    super.initState();
    setSecure(true);
  }

  @override
  void dispose() {
    setSecure(false);
    _pw.dispose();
    _pw2.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _pw.text;
    if (!p.exists) {
      if (pw.length < 8) {
        setState(() => _err = 'Минимум 8 символов');
        return;
      }
      if (pw != _pw2.text) {
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
      if (p.exists) {
        final ok = await p.unlock(pw);
        if (!ok) _err = 'Неверный пароль';
      } else {
        await p.create(pw);
      }
    } catch (e) {
      _err = 'Ошибка: $e';
    }
    _pw.clear();
    _pw2.clear();
    if (mounted) setState(() => _busy = false);
  }

  Widget _lockForm() {
    final creating = !p.exists;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.key,
                  size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                creating ? 'Мастер-пароль для паролей' : 'Хранилище паролей',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              if (creating)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Отдельный пароль и отдельный ключ шифрования. Восстановить его нельзя.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Pal.secondary(context), fontSize: 13),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _pw,
                obscureText: true,
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
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_err!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Pal.error(context))),
                ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(creating ? 'Создать' : 'Открыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEntry(PassEntry e, {bool isNew = false}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PassEntryScreen(pass: p, entry: e, isNew: isNew),
    ));
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json', 'xml', '1pif', 'kdbx'],
      withData: true,
    );
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      final f = r.files.first;
      final list = PassIO.import(f.name, utf8.decode(f.bytes!, allowMalformed: true));
      p.entries.addAll(list);
      p.changed();
      if (mounted) toast(context, 'Импортировано записей: ${list.length}');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _export(String kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Экспорт паролей'),
        content: const Text(
            'Файл будет сохранён в открытом виде, без шифрования. Храните его осторожно и удалите после использования.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Экспортировать')),
        ],
      ),
    );
    if (ok != true) return;
    final list = p.visible;
    String text, name;
    switch (kind) {
      case 'bwjson':
        text = PassIO.exportBitwardenJson(list);
        name = 'bitwarden_export.json';
        break;
      case 'bwcsv':
        text = PassIO.exportBitwardenCsv(list);
        name = 'bitwarden_export.csv';
        break;
      case 'kp':
        text = PassIO.exportKeepassXml(list);
        name = 'keepass_export.xml';
        break;
      default:
        text = PassIO.exportCsv(list);
        name = 'passwords.csv';
    }
    final saved = await saveBytes(name, utf8.encode(text));
    if (saved && mounted) toast(context, 'Файл сохранён');
  }

  Widget _list() {
    final all = p.visible;
    final folders = all.map((e) => e.folder).where((f) => f.isNotEmpty).toSet().toList()
      ..sort();
    var list = all;
    if (_folder == '\u0000fav') {
      list = list.where((e) => e.favorite).toList();
    } else if (_folder != '\u0000all') {
      list = list.where((e) => e.folder == _folder).toList();
    }
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    Widget chip(String key, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: _folder == key,
            onSelected: (_) => setState(() => _folder = key),
          ),
        );

    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                    hintText: 'Поиск',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'lock') {
                  p.lock();
                } else if (v == 'imp') {
                  _import();
                } else {
                  _export(v);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'imp', child: Text('Импорт…')),
                PopupMenuItem(value: 'csv', child: Text('Экспорт CSV')),
                PopupMenuItem(value: 'bwjson', child: Text('Экспорт Bitwarden JSON')),
                PopupMenuItem(value: 'bwcsv', child: Text('Экспорт Bitwarden CSV')),
                PopupMenuItem(value: 'kp', child: Text('Экспорт KeePass XML')),
                PopupMenuItem(value: 'lock', child: Text('Заблокировать')),
              ],
            ),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              chip('\u0000all', 'Все'),
              chip('\u0000fav', '★ Избранное'),
              for (final f in folders) chip(f, f),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text('Записей нет',
                      style: TextStyle(color: Pal.secondary(context))))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  children: [
                    for (final e in list)
                      AppCard(
                        onTap: () => _openEntry(e),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Avatar(e.title, 0xFF5856D6, radius: 18),
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
                          if (e.favorite)
                            const Icon(Icons.star,
                                size: 16, color: Color(0xFFFF9500)),
                          IconButton(
                            tooltip: 'Копировать пароль',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              copyClear(e.password);
                              toast(context, 'Пароль скопирован (очистится через 30 с)');
                            },
                          ),
                        ]),
                      ),
                  ],
                ),
        ),
      ]),
      Fab(onPressed: () => _openEntry(PassEntry.create(), isNew: true)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: p,
      builder: (context, _) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => p.touch(),
        child: p.unlocked ? _list() : _lockForm(),
      ),
    );
  }
}

// =============================================================== запись

class PassEntryScreen extends StatefulWidget {
  final PassStore pass;
  final PassEntry entry;
  final bool isNew;
  const PassEntryScreen(
      {super.key, required this.pass, required this.entry, required this.isNew});
  @override
  State<PassEntryScreen> createState() => _PassEntryScreenState();
}

class _PassEntryScreenState extends State<PassEntryScreen> {
  late final TextEditingController _title,
      _user,
      _pw,
      _url,
      _folder,
      _totp,
      _notes;
  bool _show = false;
  bool _fav = false;
  Timer? _tick;
  String _code = '';

  PassEntry get e => widget.entry;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: e.title);
    _user = TextEditingController(text: e.username);
    _pw = TextEditingController(text: e.password);
    _url = TextEditingController(text: e.url);
    _folder = TextEditingController(text: e.folder);
    _totp = TextEditingController(text: e.totp);
    _notes = TextEditingController(text: e.notes);
    _fav = e.favorite;
    setSecure(true);
    _refreshCode();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _refreshCode());
  }

  @override
  void dispose() {
    _tick?.cancel();
    setSecure(false);
    for (final c in [_title, _user, _pw, _url, _folder, _totp, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshCode() async {
    final s = _totp.text.trim();
    final c = s.isEmpty ? '' : await totpCode(s);
    if (mounted) setState(() => _code = c);
  }

  void _save() {
    final old = e.password;
    if (!widget.isNew && old.isNotEmpty && old != _pw.text) {
      e.history.insert(0, {'p': old, 'at': nowMs()});
      if (e.history.length > 20) e.history.removeRange(20, e.history.length);
    }
    e.title = _title.text.trim();
    e.username = _user.text.trim();
    e.password = _pw.text;
    e.url = _url.text.trim();
    e.folder = _folder.text.trim();
    e.totp = _totp.text.trim();
    e.notes = _notes.text;
    e.favorite = _fav;
    e.updatedAt = nowMs();
    if (widget.isNew) widget.pass.entries.add(e);
    widget.pass.changed();
    Navigator.pop(context);
  }

  void _delete() {
    e.deleted = true;
    e.updatedAt = nowMs();
    widget.pass.changed();
    Navigator.pop(context);
  }

  Widget _copyCtl(TextEditingController c) => IconButton(
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          copyClear(c.text);
          toast(context, 'Скопировано (очистится через 30 с)');
        },
      );

  Widget _copyBtn(String text) => IconButton(
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          copyClear(text);
          toast(context, 'Скопировано (очистится через 30 с)');
        },
      );

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.pass.touch(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'Новая запись' : 'Запись'),
          actions: [
            IconButton(
              icon: Icon(_fav ? Icons.star : Icons.star_border),
              onPressed: () => setState(() => _fav = !_fav),
            ),
            if (!widget.isNew)
              IconButton(
                  icon: const Icon(Icons.delete_outline), onPressed: _delete),
            TextButton(onPressed: _save, child: const Text('Сохранить')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                  labelText: 'Логин', suffixIcon: _copyCtl(_user)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pw,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: 'Пароль',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                        size: 18),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    tooltip: 'Сгенерировать',
                    onPressed: () async {
                      final g = await showGenerator(context);
                      if (g != null) setState(() => _pw.text = g);
                    },
                  ),
                  _copyCtl(_pw),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _url,
                decoration: const InputDecoration(labelText: 'Адрес (URL)')),
            const SizedBox(height: 12),
            TextField(
                controller: _folder,
                decoration: const InputDecoration(labelText: 'Папка')),
            const SizedBox(height: 12),
            TextField(
              controller: _totp,
              onChanged: (_) => _refreshCode(),
              decoration: const InputDecoration(
                  labelText: 'TOTP-секрет (или otpauth://…)'),
            ),
            if (_code.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Text('${_code.substring(0, 3)} ${_code.substring(3)}',
                      style: const TextStyle(
                          fontSize: 28,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Text('${totpSecondsLeft()} с',
                      style: TextStyle(color: Pal.secondary(context))),
                  _copyBtn(_code),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Заметки'),
            ),
            if (e.history.isNotEmpty) ...[
              const SectionTitle('История паролей'),
              for (final h in e.history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('•' * min(12, (h['p'] as String).length)),
                  subtitle: Text(fmtDate((h['at'] as num).toInt())),
                  trailing: _copyBtn(h['p'] as String),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

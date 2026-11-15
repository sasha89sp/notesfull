part of 'pass_page.dart';


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
    if (widget.embedded) {
      widget.onDone?.call();
      if (mounted) toast(context, 'Сохранено');
    } else {
      Navigator.pop(context);
    }
  }

  void _delete() {
    e.deleted = true;
    e.updatedAt = nowMs();
    widget.pass.changed();
    if (widget.embedded) {
      widget.onDone?.call();
    } else {
      Navigator.pop(context);
    }
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
          automaticallyImplyLeading: !widget.embedded,
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
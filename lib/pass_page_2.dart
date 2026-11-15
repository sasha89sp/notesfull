part of 'pass_page.dart';

extension _ExtPassPageState1 on _PassPageState {

  PassStore get p => widget.pass;

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
        if (!ok) {
          _err = 'Неверный пароль';
        } else if (_save) {
          await p.rememberPassword(pw, _saveMin);
        }
      } else {
        await p.create(pw);
        if (_save) await p.rememberPassword(pw, _saveMin);
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Сохранить пароль'),
                value: _save,
                onChanged: (v) => setState(() => _save = v ?? false),
              ),
              if (_save)
                Row(children: [
                  const Expanded(child: Text('На срок')),
                  DropdownButton<int>(
                    value: _saveMin,
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 минут')),
                      DropdownMenuItem(value: 30, child: Text('30 минут')),
                      DropdownMenuItem(value: 60, child: Text('1 час')),
                      DropdownMenuItem(value: 1440, child: Text('1 день')),
                      DropdownMenuItem(value: -1, child: Text('До выхода из профиля')),
                    ],
                    onChanged: (v) => setState(() => _saveMin = v ?? 30),
                  ),
                ]),
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

  Future<String?> _askName(String title, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Готово')),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _newFolder() async {
    final n = await _askName('Новая папка');
    if (n != null) p.createFolder(n);
  }

  Future<void> _folderMenu(String name) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(ctx, 'ren')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить папку (записи сохранятся)'),
              onTap: () => Navigator.pop(ctx, 'del')),
        ]),
      ),
    );
    if (act == 'ren') {
      final n = await _askName('Переименовать папку', name);
      if (n != null) {
        p.renameFolder(name, n);
        if (_folder == name) setState(() => _folder = n);
      }
    } else if (act == 'del') {
      p.deleteFolder(name);
      if (_folder == name) setState(() => _folder = '\u0000all');
    }
  }
}

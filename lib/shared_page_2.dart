// ▸ Часть shared_page.dart: Раздел «Общая папка»: группы, приглашения, участники  [содержит: _FolderPickerState, _CreateDialog, _CreateDialogState, GroupScreen]
part of 'shared_page.dart';


class _FolderPickerState extends State<_FolderPicker> {
  late String _path;
  List<String> _dirs = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _path = widget.start.isEmpty ? '/' : widget.start;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final l = await widget.dav.listDirs(_path);
      l.removeWhere((e) => e.startsWith('.'));
      l.sort();
      if (mounted) {
        setState(() {
          _dirs = l;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = '$e';
          _loading = false;
        });
      }
    }
  }

  String _join(String n) => _path == '/' ? '/$n' : '$_path/$n';

  void _up() {
    if (_path == '/') return;
    final i = _path.lastIndexOf('/');
    _path = i <= 0 ? '/' : _path.substring(0, i);
    _load();
  }

  Future<void> _mk() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Имя')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Создать')),
        ],
      ),
    );
    final n = c.text.trim().replaceAll('/', '');
    c.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      await widget.dav.mkcolAll(_join(n));
      _path = _join(n);
      await _load();
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        IconButton(onPressed: _path == '/' ? null : _up, icon: const Icon(Icons.arrow_upward)),
        Expanded(child: Text(_path, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: 'Создать папку', onPressed: _mk, icon: const Icon(Icons.create_new_folder_outlined)),
      ]),
      content: SizedBox(
        width: 360,
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(child: Text(_err!, style: TextStyle(color: Pal.error(context))))
                : _dirs.isEmpty
                    ? const Center(child: Text('Вложенных папок нет'))
                    : ListView(children: [
                        for (final d in _dirs)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(d),
                            onTap: () {
                              _path = _join(d);
                              _load();
                            },
                          ),
                      ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(context, _path), child: const Text('Выбрать эту папку')),
      ],
    );
  }
}

class _CreateDialog extends StatefulWidget {
  final Store store;
  const _CreateDialog({required this.store});

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _path = TextEditingController();
  final _id = TextEditingController(text: Groups.stamp());
  final _phrase = TextEditingController();
  bool _own = false;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final st = widget.store.settings;
    if (st.storage == 'webdav' && st.syncConfigured) {
      // данные текущей авторизации подставляются сами, их можно изменить
      _url.text = st.url;
      _user.text = st.user;
      _pass.text = st.pass;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _pass, _path, _id, _phrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _browse() async {
    if (_url.text.trim().isEmpty) return setState(() => _err = 'Сначала укажите WebDAV-сервер');
    final r = Dav(_url.text.trim(), _user.text.trim(), _pass.text);
    final p = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPicker(dav: r, start: _path.text.trim().startsWith('/') ? _path.text.trim() : '/'),
    );
    if (p != null) setState(() => _path.text = p);
  }

  Future<void> _ok() async {
    if (_name.text.trim().isEmpty) return setState(() => _err = 'Введите название');
    if (_path.text.trim().isEmpty) return setState(() => _err = 'Выберите папку или введите путь');
    if (_own && _phrase.text.length < 6) {
      return setState(() => _err = 'Ключ: минимум 6 символов');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final g = await Groups.create(widget.store,
          name: _name.text,
          folder: _path.text,
          url: _url.text,
          user: _user.text,
          pass: _pass.text,
          id: _id.text,
          phrase: _own ? _phrase.text : null);
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая общая папка'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            const Text('Сервер', style: TextStyle(fontWeight: FontWeight.w600)),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'WebDAV-сервер')),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Логин')),
            TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль')),
            const SizedBox(height: 10),
            const Text('Папка на сервере', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _path,
                    decoration: const InputDecoration(labelText: 'Путь, например /Family')),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: 'Открыть папку',
                  onPressed: _browse,
                  icon: const Icon(Icons.folder_open)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _id,
              decoration: InputDecoration(
                labelText: 'Уникальный ID',
                helperText: 'Дата и время с секундами; можно ввести свой',
                suffixIcon: IconButton(
                    tooltip: 'Сгенерировать заново',
                    onPressed: () => setState(() => _id.text = Groups.stamp()),
                    icon: const Icon(Icons.refresh)),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Ключ шифрования', style: TextStyle(fontWeight: FontWeight.w600)),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Сгенерировать')),
                ButtonSegment(value: true, label: Text('Свой')),
              ],
              selected: {_own},
              onSelectionChanged: (v) => setState(() => _own = v.first),
            ),
            if (_own)
              TextField(
                  controller: _phrase,
                  decoration: const InputDecoration(labelText: 'Ваш ключ (фраза)')),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_err!, style: TextStyle(color: Pal.error(context))),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: _busy ? null : _ok, child: const Text('ОК')),
      ],
    );
  }
}

/// Внутри группы: Чат и Заметки (полный функционал заметок с комментариями).
class GroupScreen extends StatefulWidget {
  final Store store;
  final Group group;
  const GroupScreen({super.key, required this.store, required this.group});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}
part of 'shell.dart';

extension _ExtShellState1 on _ShellState {

  Store get s => widget.store;

  bool _on(String m) => s.settings.moduleOn(m);

  /// Активные разделы: отключённые модули не показываются и не загружаются.
  List<String> get _mods => [
        'home',
        if (_on('notes')) 'notes',
        if (_on('shared')) 'shared',
        if (_on('calendar')) 'calendar',
        if (_on('pass')) 'pass',
        if (_on('voice')) 'voice',
        if (_on('windows') && Platform.isWindows) 'windows',
        if (_on('dock') && DockMode.supported) 'dock',
        if (_on('backup')) 'backup',
      ];

  /// В нижней панели — не больше пяти пунктов; «Бэкап» только в меню.
  List<String> get _navMods => _mods.where((m) => m != 'backup' && m != 'voice' && m != 'windows' && m != 'dock').toList();

  void _go(String m) => setState(() {
        // выход из модуля с блокировкой: время бездействия считается с этого момента
        if (_tab != m && s.settings.modLock.containsKey(_tab) && !s.moduleLocked(_tab)) {
          s.moduleTouch(_tab);
        }
        _tab = m;
        _visited.add(m);
        if (m == 'shared' && s.settings.sharedOnOpen && s.settings.groups.isNotEmpty) {
          s.settings.sharedLast = 0;
          Future<void>.microtask(() => s.syncAll(auto: true));
        }
      });

  String get _title => _ShellState._names[_tab] ?? 'Главная';

  void _newNote() {
    final n = Note.create(s.author, s.profileId, 'personal');
    s.notes.add(n);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EditorScreen(store: s, note: n)));
  }

  void _newEvent({bool task = false}) {
    final e = CalEvent.create(DateTime.now(), task: task);
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EventScreen(store: s, event: e, isNew: true)));
  }

  void _quickCreate() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Новая заметка'),
            onTap: () {
              Navigator.pop(ctx);
              _newNote();
            },
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Новое событие'),
            onTap: () {
              Navigator.pop(ctx);
              _newEvent();
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Новая задача'),
            onTap: () {
              Navigator.pop(ctx);
              _newEvent(task: true);
            },
          ),
        ]),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
            store: s, onTheme: widget.onTheme, onLogout: widget.onLogout)));
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback f,
      {bool selected = false}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        f();
      },
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(t,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
      );

  Widget _drawer() {
    final tags = <String>{};
    if (_on('notes')) {
      for (final n in s.notes.where((n) => !n.deleted && !n.isGroup)) {
        tags.addAll(n.tags);
      }
    }
    final sortedTags = tags.toList()..sort();
    final favFolders = _on('notes')
        ? s.folders
            .where((f) => !f.deleted && s.isFolderFav(f.id))
            .toList()
        : <NoteFolder>[];
    final favNotes = _on('notes')
        ? s.notes.where((n) => !n.deleted && !n.isGroup && n.favorite).toList()
        : <Note>[];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Avatar(s.author, s.settings.color, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.author,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            _section('МОДУЛИ'),
            if (_on('notes'))
              _drawerItem(Icons.notes, 'Заметки', () {
                setState(() {
                  _folder = '';
                  _folderSeq++;
                  _tag = null;
                });
                _go('notes');
              }, selected: _tab == 'notes'),
            if (_on('shared'))
              _drawerItem(
                  Icons.folder_shared_outlined, 'Общая папка', () => _go('shared'),
                  selected: _tab == 'shared'),
            if (_on('calendar'))
              _drawerItem(Icons.calendar_month_outlined, 'Календарь',
                  () => _go('calendar'),
                  selected: _tab == 'calendar'),
            if (_on('pass'))
              _drawerItem(Icons.key_outlined, 'Пароли', () => _go('pass'),
                  selected: _tab == 'pass'),
            if (_on('voice'))
              _drawerItem(Icons.mic_none, 'Диктовка', () => _go('voice'), selected: _tab == 'voice'),
            if (_on('backup'))
              _drawerItem(Icons.backup_outlined, 'Бэкап', () => _go('backup'),
                  selected: _tab == 'backup'),
            if (favFolders.isNotEmpty || favNotes.isNotEmpty) ...[
              const Divider(),
              _section('ИЗБРАННОЕ'),
              for (final f in favFolders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _folder = f.id;
                      _folderSeq++;
                      _tag = null;
                    });
                    _go('notes');
                  },
                ),
              for (final n in favNotes)
                ListTile(
                  leading: const Icon(Icons.star_border),
                  title: Text(n.title.isEmpty ? 'Без названия' : n.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => EditorScreen(store: s, note: n)));
                  },
                ),
            ],
            if (sortedTags.isNotEmpty) ...[
              const Divider(),
              _section('ТЕГИ'),
              for (final t in sortedTags)
                ListTile(
                  leading: Icon(Icons.tag, color: tagColor(t)),
                  title: Text(t),
                  selected: _tag == t,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _folder = '';
                      _folderSeq++;
                      _tag = t;
                    });
                    _go('notes');
                  },
                ),
            ],
          ])),
          const Divider(height: 1),
          if (_on('notes'))
            _drawerItem(Icons.delete_outline, 'Корзина', () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => TrashScreen(store: s)));
            }),
          _drawerItem(Icons.settings_outlined, 'Настройки', _openSettings),
          _drawerItem(Icons.desktop_windows_outlined, 'Вид: компьютер', () {
            s.settings.uiMode = 'desktop';
            s.saveSettings();
            s.refresh();
          }),
          ListTile(
            leading: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: Text(dark ? 'Светлая тема' : 'Тёмная тема'),
            onTap: () {
              s.settings.theme = dark ? 'light' : 'dark';
              s.saveSettings();
              widget.onTheme(s.settings.theme);
            },
          ),
        ]),
      ),
    );
  }
}

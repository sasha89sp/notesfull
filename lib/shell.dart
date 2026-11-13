import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'backup.dart';
import 'backup_page.dart';
import 'calendar_page.dart';
import 'desktop.dart';
import 'editor.dart';
import 'event_screen.dart';
import 'models.dart';
import 'notes_page.dart';
import 'pass_page.dart';
import 'pass_store.dart';
import 'settings_screen.dart';
import 'shared_page.dart';
import 'store.dart';
import 'widgets.dart';

/// Главная оболочка: нижняя навигация, боковое меню (профиль, модули,
/// «Избранное», настройки, тема), кнопка и строка статуса синхронизации сверху.
class Shell extends StatefulWidget {
  final Store store;
  final PassStore pass;
  final void Function(String theme) onTheme;
  final Future<void> Function(bool picker) onLogout;
  const Shell(
      {super.key,
      required this.store,
      required this.pass,
      required this.onLogout,
      required this.onTheme});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  String _tab = 'home';
  final Set<String> _visited = {'home'};
  String? _tag;
  String _folder = ''; // папка, открытая из «Избранного»
  int _folderSeq = 0;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _conn;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.syncAll();
    Backup.autoIfDue(s);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      s.syncAll();
      Backup.autoIfDue(s);
    });
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) s.schedSync();
    });
    if (Platform.isAndroid && !s.settings.wizardDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPermissionWizard(context, s);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _conn?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) s.syncAll();
  }

  bool _on(String m) => s.settings.moduleOn(m);

  /// Активные разделы: отключённые модули не показываются и не загружаются.
  List<String> get _mods => [
        'home',
        if (_on('notes')) 'notes',
        if (_on('shared')) 'shared',
        if (_on('calendar')) 'calendar',
        if (_on('pass')) 'pass',
        if (_on('backup')) 'backup',
      ];

  /// В нижней панели — не больше пяти пунктов; «Бэкап» только в меню.
  List<String> get _navMods => _mods.where((m) => m != 'backup').toList();

  void _go(String m) => setState(() {
        _tab = m;
        _visited.add(m);
      });

  static const _icons = {
    'home': Icons.home_outlined,
    'notes': Icons.notes,
    'shared': Icons.folder_shared_outlined,
    'calendar': Icons.calendar_month_outlined,
    'pass': Icons.key_outlined,
    'backup': Icons.backup_outlined,
  };
  static const _names = {
    'home': 'Главная',
    'notes': 'Заметки',
    'shared': 'Общая папка',
    'calendar': 'Календарь',
    'pass': 'Пароли',
    'backup': 'Бэкап',
  };

  String get _title => _names[_tab] ?? 'Главная';

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
          _drawerItem(Icons.settings_outlined, 'Настройки', _openSettings),
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

  /// Кнопка синхронизации в правом верхнем углу: во время работы нажатие останавливает.
  Widget _syncButton() {
    if (s.syncing) {
      return IconButton(
        tooltip: 'Остановить синхронизацию',
        onPressed: s.cancelSync,
        icon: Stack(alignment: Alignment.center, children: [
          SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, value: s.progress)),
          const Icon(Icons.stop, size: 12),
        ]),
      );
    }
    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: 'Синхронизировать',
      onPressed: () {
        if (!s.settings.syncConfigured && !s.settings.googleConfigured) {
          _openSettings();
        } else {
          s.syncAll();
        }
      },
    );
  }

  /// Слева от кнопки: процент и что сейчас происходит (или итог последней).
  Widget _syncStatus() {
    String text;
    Color col = Pal.secondary(context);
    if (s.syncing) {
      final p = s.progress;
      final pc = p == null ? '' : '${(p * 100).round()}% · ';
      text = '$pc${s.progressText}';
    } else {
      final last = s.lastSync;
      if (last == null) return const SizedBox.shrink();
      text = last.status == 'ok' ? 'Синхронизировано ${last.when}' : last.statusText;
      if (last.status != 'ok' && last.status != 'cancelled') col = Pal.error(context);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Text(text,
          maxLines: 2,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, height: 1.2, color: col)),
    );
  }

  /// Страницы строятся лениво: модуль загружается при первом открытии.
  Widget _page(String m) {
    if (m != _tab && !_visited.contains(m)) return const SizedBox.shrink();
    switch (m) {
      case 'home':
        return _on('notes')
            ? NotesList(
                key: const ValueKey('home'),
                store: s,
                filter: 'all',
                tag: null,
                home: true,
                onOpenFolder: (id) {
                  setState(() {
                    _folder = id;
                    _folderSeq++;
                  });
                  _go('notes');
                },
                onClearTag: () {})
            : _ModulesHome(mods: _mods, onOpen: _go);
      case 'notes':
        return NotesList(
            key: ValueKey('notes$_folderSeq'),
            store: s,
            filter: 'all',
            tag: _tag,
            home: false,
            folder: _folder,
            onClearTag: () => setState(() => _tag = null));
      case 'shared':
        return SharedPage(store: s);
      case 'calendar':
        return CalendarPage(store: s);
      case 'pass':
        return _tab == 'pass'
            ? PassPage(store: s, pass: widget.pass)
            : const SizedBox.shrink();
      case 'backup':
        return BackupPage(store: s);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _body() {
    final mods = _mods;
    if (!mods.contains(_tab)) _tab = 'home';
    return IndexedStack(
        index: mods.indexOf(_tab), children: [for (final m in mods) _page(m)]);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CalEvent?>(
      valueListenable: Desktop.I.alert,
      builder: (context, alert, _) {
        if (alert != null) return _AlertView(event: alert);
        return AnimatedBuilder(
          animation: s,
          builder: (context, _) {
            final nav = _navMods;
            return Scaffold(
              appBar: AppBar(
                title: Text(_title,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                actions: [
                  Flexible(child: _syncStatus()),
                  _syncButton(),
                  const SizedBox(width: 4),
                ],
              ),
              drawer: _drawer(),
              body: Stack(children: [
                _body(),
                if (_tab == 'home' && _on('notes')) Fab(onPressed: _quickCreate),
              ]),
              bottomNavigationBar: NavigationBar(
                selectedIndex: nav.contains(_tab) ? nav.indexOf(_tab) : 0,
                onDestinationSelected: (i) => _go(nav[i]),
                destinations: [
                  for (final m in nav)
                    NavigationDestination(icon: Icon(_icons[m]), label: _names[m]!),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Окно-напоминание (Windows): висит, пока не закроют, со звуком.
class _AlertView extends StatelessWidget {
  final CalEvent event;
  const _AlertView({required this.event});

  @override
  Widget build(BuildContext context) {
    final when = event.allDay
        ? fmtDay(event.startDt)
        : '${fmtDay(event.startDt)}, ${fmtTime(event.startDt)}';
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(event.isTask ? Icons.check_circle_outline : Icons.notifications_active,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(event.isTask ? 'Задача' : 'Напоминание',
                  style: TextStyle(color: Pal.secondary(context))),
            ]),
            const SizedBox(height: 10),
            Text(event.title.isEmpty ? 'Без названия' : event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(when, style: TextStyle(color: Pal.secondary(context))),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Desktop.I.closeAlert(open: false),
                  child: const Text('Закрыть')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => Desktop.I.closeAlert(open: true),
                  child: const Text('Открыть')),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Главная, когда модуль «Заметки» отключён: быстрые переходы к включённым модулям.
class _ModulesHome extends StatelessWidget {
  final List<String> mods;
  final void Function(String) onOpen;
  const _ModulesHome({required this.mods, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const names = {
      'calendar': 'Календарь',
      'pass': 'Пароли',
      'shared': 'Общая папка',
      'backup': 'Бэкап',
    };
    const icons = {
      'calendar': Icons.calendar_month_outlined,
      'pass': Icons.key_outlined,
      'shared': Icons.folder_shared_outlined,
      'backup': Icons.backup_outlined,
    };
    final l = mods.where((m) => names.containsKey(m)).toList();
    if (l.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Все модули отключены. Включите нужные в Настройки → Модули.',
                  textAlign: TextAlign.center)));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final m in l)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: ListTile(
              leading: Icon(icons[m]),
              title: Text(names[m]!),
              onTap: () => onOpen(m),
            ),
          ),
        ),
    ]);
  }
}

// ▸ Часть shell.dart: Оболочка: вкладки, боковое меню (телефон), левая панель (компьютер), модули  [содержит: _ExtShellState2, _AlertView, _ModulesHome]
part of 'shell.dart';

extension _ExtShellState2 on _ShellState {

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
    // в модуле — синхронизация только его данных; в остальных разделах — всё
    final scope = const {'home': 'notes', 'notes': 'notes', 'calendar': 'calendar', 'shared': 'shared'}[_tab] ?? 'all';
    final what = const {'notes': 'заметки', 'calendar': 'календарь', 'shared': 'общую папку'}[scope];
    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: what == null ? 'Синхронизировать всё' : 'Синхронизировать: $what',
      onPressed: () {
        if (!s.settings.syncConfigured && !s.settings.googleConfigured) {
          _openSettings();
        } else {
          s.syncAll(scope: scope);
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
      final (u, d) = Net.speed();
      text = '$pc↓${Net.fmtSpeed(d)} ↑${Net.fmtSpeed(u)}\n${s.progressText}';
    } else {
      final last = s.lastSync;
      if (last == null) return const SizedBox.shrink();
      text = last.status == 'ok' ? 'Синхронизировано ${last.when}' : last.statusText;
      if (last.status != 'ok' && last.status != 'cancelled') col = Pal.error(context);
    }
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => DiagHub(store: s, tab: 0))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(text,
            maxLines: 2,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, height: 1.2, color: col)),
      ),
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
        // десктоп с широким окном: три колонки, как в Joplin
        if (s.useDesktop(MediaQuery.of(context).size.width)) {
          return DesktopNotes(
              key: ValueKey('dn$_folderSeq'),
              store: s,
              initial: _folder.isNotEmpty ? 'f:$_folder' : _tag != null ? 't:$_tag' : 'all');
        }
        return NotesList(
            key: ValueKey('notes$_folderSeq'),
            store: s,
            filter: 'all',
            tag: _tag,
            home: false,
            folder: _folder,
            onClearTag: () => setState(() => _tag = null));
      case 'shared':
        return _gate('shared', SharedPage(store: s));
      case 'calendar':
        return CalendarPage(store: s);
      case 'pass':
        return _tab == 'pass'
            ? _gate('pass', PassPage(store: s, pass: widget.pass, desktop: s.useDesktop(MediaQuery.of(context).size.width)))
            : const SizedBox.shrink();
      case 'voice':
        return VoicePage(store: s);
      case 'windows':
        return WinPage(store: s);
      case 'dock':
        return DockPage(store: s);
      case 'backup':
        return BackupPage(store: s);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Блокировка модуля биометрией (по настройкам, отдельно для общей папки и паролей).
  Widget _gate(String m, Widget page) {
    if (_tab != m) return page;
    if (!s.settings.modLock.containsKey(m)) return page;
    if (!s.moduleLocked(m)) {
      s.moduleTouch(m);
      return page;
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline, size: 44),
        const SizedBox(height: 12),
        Text('${_ShellState._names[m]} заблокирован'),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.fingerprint),
          label: const Text('Разблокировать'),
          onPressed: () async {
            final ok = await s.unlockModule(m);
            if (mounted) {
              setState(() {});
              if (!ok) toast(context, 'Не удалось подтвердить личность');
            }
          },
        ),
      ]),
    );
  }

  Widget _body() {
    final mods = _mods;
    if (!mods.contains(_tab)) _tab = 'home';
    return IndexedStack(
        index: mods.indexOf(_tab), children: [for (final m in mods) _page(m)]);
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
      'voice': 'Диктовка',
      'backup': 'Бэкап',
    };
    const icons = {
      'calendar': Icons.calendar_month_outlined,
      'pass': Icons.key_outlined,
      'shared': Icons.folder_shared_outlined,
      'voice': Icons.mic_none,
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
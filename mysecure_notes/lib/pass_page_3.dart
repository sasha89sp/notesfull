part of 'pass_page.dart';

extension _ExtPassPageState2 on _PassPageState {

  Widget _list() {
    final all = p.visible;
    final folders = p.folderNames;
    var list = all;
    if (_folder == '\u0000fav') {
      list = list.where((e) => e.favorite).toList();
    } else if (_folder == '\u0000none') {
      list = list.where((e) => e.folder.isEmpty).toList();
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

    Widget chip(String key, String label, {bool folder = false}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onLongPress: folder ? () => _folderMenu(key) : null,
            child: ChoiceChip(
              label: Text(label),
              selected: _folder == key,
              onSelected: (_) => setState(() => _folder = key),
            ),
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
                  p.forgetSaved();
                  p.lock();
                } else if (v == 'forget') {
                  p.forgetSaved();
                  toast(context, 'Сохранённый пароль забыт');
                } else if (v == 'imp') {
                  _import();
                } else {
                  _export(v);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'imp', child: Text('Импорт (Bitwarden, KeePass XML, CSV…)')),
                const PopupMenuItem(value: 'csv', child: Text('Экспорт: CSV')),
                const PopupMenuItem(value: 'bwjson', child: Text('Экспорт: Bitwarden JSON')),
                const PopupMenuItem(value: 'bwcsv', child: Text('Экспорт: Bitwarden CSV')),
                const PopupMenuItem(value: 'kp', child: Text('Экспорт: KeePass XML')),
                if (p.savedActive)
                  const PopupMenuItem(
                      value: 'forget', child: Text('Забыть сохранённый пароль')),
                const PopupMenuItem(value: 'lock', child: Text('Заблокировать')),
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
              chip('\u0000none', 'Без папки'),
              for (final f in folders) chip(f, f, folder: true),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Папка'),
                  onPressed: _newFolder,
                ),
              ),
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

  // ------------------------------------------------------------ десктоп: три блока

  List<PassEntry> _filtered() {
    var list = p.visible;
    if (_folder == '\u0000fav') {
      list = list.where((e) => e.favorite).toList();
    } else if (_folder == '\u0000none') {
      list = list.where((e) => e.folder.isEmpty).toList();
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
    return list;
  }

  Widget _dRow(IconData icon, String label, String key, {String? folderName}) {
    final sel = _folder == key;
    final cs = Theme.of(context).colorScheme;
    return CtxArea(
      onTap: () => setState(() => _folder = key),
      onMenu: (pos) async {
        if (folderName == null) {
          final a = await showCtx(context, pos, const [CtxItem('new', 'Новая папка', icon: Icons.create_new_folder_outlined)]);
          if (a == 'new') await _newFolder();
          return;
        }
        final a = await showCtx(context, pos, const [
          CtxItem('ren', 'Переименовать', icon: Icons.edit_outlined),
          CtxItem('-', ''),
          CtxItem('del', 'Удалить папку (записи сохранятся)', icon: Icons.delete_outline, danger: true),
        ]);
        if (a == 'ren') {
          final n = await _askName('Переименовать папку', folderName);
          if (n != null) {
            p.renameFolder(folderName, n);
            if (_folder == folderName) setState(() => _folder = n);
          }
        } else if (a == 'del') {
          p.deleteFolder(folderName);
          if (_folder == folderName) setState(() => _folder = '\u0000all');
        }
      },
      child: Container(
        color: sel ? cs.primary.withOpacity(0.14) : null,
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        child: Row(children: [
          Icon(icon, size: 15, color: sel ? cs.primary : null),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
        ]),
      ),
    );
  }

  Widget _dSide() => ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
        _dRow(Icons.vpn_key_outlined, 'Все записи', '\u0000all'),
        _dRow(Icons.star_border, 'Избранное', '\u0000fav'),
        _dRow(Icons.folder_off_outlined, 'Без папки', '\u0000none'),
        for (final f in p.folderNames) _dRow(Icons.folder_outlined, f, f, folderName: f),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 15),
            label: const Text('Новая папка'),
          ),
        ),
      ]);
}

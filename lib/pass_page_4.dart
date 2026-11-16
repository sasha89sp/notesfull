// ▸ Часть pass_page.dart: Экран паролей: мобильный список и компьютерный вид в три блока, карточка записи  [содержит: _ExtPassPageState3, PassEntryScreen]
part of 'pass_page.dart';

extension _ExtPassPageState3 on _PassPageState {

  Future<void> _entryMenu(PassEntry e, Offset pos) async {
    final a = await showCtx(context, pos, [
      const CtxItem('open', 'Открыть', icon: Icons.open_in_new),
      const CtxItem('user', 'Копировать логин', icon: Icons.person_outline),
      const CtxItem('pass', 'Копировать пароль', icon: Icons.key_outlined),
      if (e.url.trim().isNotEmpty) const CtxItem('url', 'Открыть сайт', icon: Icons.language),
      CtxItem('fav', e.favorite ? 'Убрать из избранного' : 'В избранное',
          icon: e.favorite ? Icons.star : Icons.star_border),
      const CtxItem('-', ''),
      const CtxItem('del', 'Удалить', icon: Icons.delete_outline, danger: true),
    ]);
    if (a == null || !mounted) return;
    switch (a) {
      case 'open':
        setState(() {
          _sel = e;
          _selNew = false;
          _selSeq++;
        });
        break;
      case 'user':
        copyClear(e.username);
        toast(context, 'Логин скопирован (очистится через 30 с)');
        break;
      case 'pass':
        copyClear(e.password);
        toast(context, 'Пароль скопирован (очистится через 30 с)');
        break;
      case 'url':
        var u = e.url.trim();
        if (!u.contains('://')) u = 'https://$u';
        await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
        break;
      case 'fav':
        e.favorite = !e.favorite;
        e.updatedAt = nowMs();
        p.changed();
        break;
      case 'del':
        e.deleted = true;
        e.updatedAt = nowMs();
        p.changed();
        if (_sel?.id == e.id) setState(() => _sel = null);
        break;
    }
  }

  Widget _dList() {
    final list = _filtered();
    final sec = Pal.secondary(context);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 0, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Поиск', prefixIcon: Icon(Icons.search, size: 16)),
            ),
          ),
          IconButton(
              tooltip: 'Новая запись',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _sel = PassEntry.create();
                _selNew = true;
                _selSeq++;
              }),
              icon: const Icon(Icons.add, size: 20)),
          PopupMenuButton<String>(
            iconSize: 18,
            padding: EdgeInsets.zero,
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
              if (p.savedActive) const PopupMenuItem(value: 'forget', child: Text('Забыть сохранённый пароль')),
              const PopupMenuItem(value: 'lock', child: Text('Заблокировать')),
            ],
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text('Записей нет', style: TextStyle(color: sec, fontSize: 12.5)))
            : ListView.builder(
                itemCount: list.length,
                itemExtent: 44,
                itemBuilder: (_, i) {
                  final e = list[i];
                  final sel = _sel?.id == e.id;
                  return CtxArea(
                    onTap: () => setState(() {
                      _sel = e;
                      _selNew = false;
                      _selSeq++;
                    }),
                    onMenu: (pos) => _entryMenu(e, pos),
                    child: Container(
                      color: sel ? cs.primary.withOpacity(0.14) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        Avatar(e.title, 0xFF5856D6, radius: 12),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e.title.isEmpty ? 'Без названия' : e.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            Text(e.username, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: sec, fontSize: 11)),
                          ]),
                        ),
                        if (e.favorite) const Icon(Icons.star, size: 12, color: Color(0xFFFF9500)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _dDetail() {
    final e = _sel;
    if (e == null || (e.deleted && !_selNew)) {
      return Center(
          child: Text('Выберите запись или создайте новую',
              style: TextStyle(color: Pal.secondary(context), fontSize: 13)));
    }
    return PassEntryScreen(
      key: ValueKey('${e.id}#$_selSeq'),
      pass: p,
      entry: e,
      isNew: _selNew,
      embedded: true,
      onDone: () => setState(() {
        _selNew = false;
        if (e.deleted) _sel = null;
      }),
    );
  }

  Widget _desktop() => ThreePane(store: widget.store, panes: {
        'side': PaneSpec('Папки', _dSide()),
        'list': PaneSpec('Пароли', _dList()),
        'detail': PaneSpec('Запись', _dDetail()),
      });
}


// =============================================================== запись

class PassEntryScreen extends StatefulWidget {
  final PassStore pass;
  final PassEntry entry;
  final bool isNew;
  final bool embedded; // внутри трёхблочного вида
  final VoidCallback? onDone;
  const PassEntryScreen(
      {super.key,
      required this.pass,
      required this.entry,
      required this.isNew,
      this.embedded = false,
      this.onDone});
  @override
  State<PassEntryScreen> createState() => _PassEntryScreenState();
}
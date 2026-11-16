// ▸ Часть settings_screen.dart: Экран настроек (вид, модули, хранилище, бэкап, шифрование, блокировки, экспорт)  [содержит: _ExtSettingsScreenState3]
part of 'settings_screen.dart';

extension _ExtSettingsScreenState3 on _SettingsScreenState {

  Widget _sectionCard(String title, List<Widget> kids) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Pal.muted(context))),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            decoration: BoxDecoration(
              color: Pal.card(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Pal.border(context)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
          ),
        ]),
      );

  Widget _folderRow(int i, bool sel, VoidCallback f, {bool wide = false}) {
    final fo = _SettingsScreenState._visible[i];
    final acc = Pal.accent(context);
    return InkWell(
      borderRadius: BorderRadius.circular(wide ? 6 : 10),
      onTap: f,
      child: Container(
        height: wide ? 34 : 52,
        margin: wide ? const EdgeInsets.symmetric(horizontal: 8, vertical: 1) : const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 14),
        decoration: BoxDecoration(
          color: wide ? (sel ? Pal.border(context) : null) : Pal.card(context),
          borderRadius: BorderRadius.circular(wide ? 6 : 10),
          border: wide ? null : Border.all(color: Pal.border(context)),
        ),
        child: Row(children: [
          Text(fo.$1, style: TextStyle(fontSize: wide ? 15 : 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(fo.$2,
                  style: TextStyle(
                      fontSize: wide ? 14 : 16,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: sel ? acc : null))),
          if (!wide) Icon(Icons.chevron_right, color: Pal.muted(context)),
        ]),
      ),
    );
  }

  Widget _folderBody(int i, Map<String, List<Widget>> secs) {
    final names = _SettingsScreenState._visible[i].$3;
    return ListView(
      key: ValueKey('sf$i'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        for (final n in names)
          if (secs.containsKey(n)) _sectionCard(n, secs[n]!),
        if (i == _SettingsScreenState._visible.length - 1) ...[
          const Hint('Все изменения в настройках сохраняются автоматически.'),
          AnimatedBuilder(
            animation: s,
            builder: (context, _) =>
                Text(s.status, style: TextStyle(color: Pal.secondary(context), fontSize: 13)),
          ),
        ],
      ],
    );
  }
}

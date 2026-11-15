part of 'dock.dart';


class _DockPageState extends State<DockPage> {
  Settings get st => widget.store.settings;

  Future<void> _save() async {
    await widget.store.saveSettings(touch: false);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final r = await FilePicker.platform.pickFiles();
    final path = r?.files.single.path;
    if (path == null) return;
    final base = path.split(RegExp(r'[\\/]')).last;
    final name = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    st.dockItems = [...st.dockItems, {'name': name, 'path': path, 'icon': ''}];
    await _save();
  }

  Future<void> _addFolder() async {
    final p = await FilePicker.platform.getDirectoryPath();
    if (p == null) return;
    st.dockItems = [...st.dockItems, {'name': p.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).last, 'path': p, 'icon': ''}];
    await _save();
  }

  Future<void> _setIcon(int i) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = r?.files.single.path;
    if (p == null) return;
    st.dockItems[i]['icon'] = p;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!DockMode.supported) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Док доступен только на компьютере.')));
    }
    final sec = Pal.secondary(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Hint('Панель значков у края экрана, как RocketDock: значки увеличиваются при наведении, '
          'клик запускает программу, правая кнопка — меню. Окно приложения на время становится панелью '
          'и остаётся поверх других окон; выход — правая кнопка → «Выйти из режима дока». '
          'Значки без своей картинки рисуются цветной плиткой с буквой (иконки из .exe не извлекаются).'),
      Center(
        child: FilledButton.icon(
          onPressed: () => DockMode.enter(widget.store),
          icon: const Icon(Icons.dock),
          label: const Text('Запустить док'),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(child: Text('Положение')),
        DropdownButton<String>(
          value: st.dockPos,
          items: const [
            DropdownMenuItem(value: 'bottom', child: Text('Снизу')),
            DropdownMenuItem(value: 'top', child: Text('Сверху')),
            DropdownMenuItem(value: 'left', child: Text('Слева')),
            DropdownMenuItem(value: 'right', child: Text('Справа')),
          ],
          onChanged: (v) {
            st.dockPos = v ?? 'bottom';
            _save();
          },
        ),
      ]),
      _slider('Размер значков', st.dockSize.toDouble(), 32, 96, (v) => st.dockSize = v.round(), '${st.dockSize}'),
      _slider('Увеличение при наведении', st.dockZoom, 1, 2.5, (v) => st.dockZoom = double.parse(v.toStringAsFixed(1)), '×${st.dockZoom}'),
      _slider('Непрозрачность', st.dockOpacity, 0.3, 1, (v) => st.dockOpacity = double.parse(v.toStringAsFixed(2)), '${(st.dockOpacity * 100).round()}%'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Поверх всех окон'),
        value: st.dockOnTop,
        onChanged: (v) {
          st.dockOnTop = v;
          _save();
        },
      ),
      const SectionTitle('Значки'),
      if (st.dockItems.isEmpty) Text('Пока пусто.', style: TextStyle(color: sec)),
      for (var i = 0; i < st.dockItems.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: GestureDetector(onTap: () => _setIcon(i), child: _thumb(st.dockItems[i])),
          title: Text((st.dockItems[i]['name'] ?? '') as String),
          subtitle: Text((st.dockItems[i]['path'] ?? '') as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0
                    ? null
                    : () {
                        final l = [...st.dockItems];
                        l.insert(i - 1, l.removeAt(i));
                        st.dockItems = l;
                        _save();
                      }),
            IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: i == st.dockItems.length - 1
                    ? null
                    : () {
                        final l = [...st.dockItems];
                        l.insert(i + 1, l.removeAt(i));
                        st.dockItems = l;
                        _save();
                      }),
            IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  st.dockItems = [...st.dockItems]..removeAt(i);
                  _save();
                }),
          ]),
        ),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Программа или файл')),
        OutlinedButton.icon(onPressed: _addFolder, icon: const Icon(Icons.folder_outlined, size: 18), label: const Text('Папка')),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Нажмите на значок слева, чтобы задать свою картинку (PNG/JPG).', style: TextStyle(color: sec, fontSize: 12)),
      ),
    ]);
  }

  Widget _thumb(Map<String, dynamic> it) {
    final icon = (it['icon'] ?? '') as String;
    if (icon.isNotEmpty && File(icon).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(icon), width: 36, height: 36, fit: BoxFit.cover));
    }
    final name = (it['name'] ?? '?') as String;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: HSLColor.fromAHSL(1, (name.hashCode % 360).abs().toDouble(), 0.55, 0.5).toColor(), borderRadius: BorderRadius.circular(8)),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  Widget _slider(String label, double v, double min, double max, void Function(double) set, String shown) {
    return Row(children: [
      Expanded(flex: 3, child: Text(label)),
      Expanded(
        flex: 4,
        child: Slider(
          min: min,
          max: max,
          value: v.clamp(min, max).toDouble(),
          onChanged: (x) => setState(() => set(x)),
          onChangeEnd: (_) => _save(),
        ),
      ),
      SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.right)),
    ]);
  }
}
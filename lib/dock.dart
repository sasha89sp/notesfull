import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

part 'dock_2.dart';


/// Режим «Док» (по мотивам RocketDock): окно превращается в узкую панель значков у края экрана,
/// всегда поверх окон; значки увеличиваются при наведении. Только компьютер.
class DockMode {
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static Rect? _saved;

  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> enter(Store s) async {
    if (!supported || active.value) return;
    final st = s.settings;
    _saved = await windowManager.getBounds();
    final v = ui.PlatformDispatcher.instance.views.first;
    final scr = Size(v.display.size.width / v.devicePixelRatio, v.display.size.height / v.devicePixelRatio);
    final n = math.max(1, st.dockItems.length);
    final slot = st.dockSize + 14.0;
    final thick = st.dockSize * st.dockZoom + 36;
    final long = math.min(
        (st.dockPos == 'bottom' || st.dockPos == 'top' ? scr.width : scr.height) - 40, n * slot + 60 + st.dockSize * (st.dockZoom - 1));
    final horiz = st.dockPos == 'bottom' || st.dockPos == 'top';
    final size = horiz ? Size(long, thick) : Size(thick, long);
    Offset pos;
    switch (st.dockPos) {
      case 'top':
        pos = Offset((scr.width - size.width) / 2, 4);
      case 'left':
        pos = Offset(4, (scr.height - size.height) / 2);
      case 'right':
        pos = Offset(scr.width - size.width - 4, (scr.height - size.height) / 2);
      default:
        pos = Offset((scr.width - size.width) / 2, scr.height - size.height - 52); // над панелью задач
    }
    await windowManager.setMinimumSize(const Size(60, 60));
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setSize(size);
    await windowManager.setPosition(pos);
    await windowManager.setAlwaysOnTop(st.dockOnTop);
    await windowManager.setSkipTaskbar(true);
    active.value = true;
  }

  static Future<void> exit() async {
    if (!active.value) return;
    active.value = false;
    await windowManager.setSkipTaskbar(false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(300, 200));
    final r = _saved;
    if (r != null) await windowManager.setBounds(r);
  }

  /// Запуск программы, файла или папки.
  static Future<void> launch(String path) async {
    try {
      if (Platform.isWindows || Platform.isMacOS) {
        await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      } else if (File(path).existsSync() && (File(path).statSync().mode & 0x49) != 0) {
        await Process.start(path, [], mode: ProcessStartMode.detached);
      } else {
        await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}

/// Сама панель: значки с эффектом увеличения (fisheye), правая кнопка — меню.
class DockView extends StatefulWidget {
  final Store store;
  const DockView({super.key, required this.store});
  @override
  State<DockView> createState() => _DockViewState();
}

class _DockViewState extends State<DockView> {
  double? _ptr; // координата курсора вдоль панели (null — курсор вне панели)

  Settings get st => widget.store.settings;
  bool get _horiz => st.dockPos == 'bottom' || st.dockPos == 'top';

  Alignment get _anchor {
    switch (st.dockPos) {
      case 'top':
        return Alignment.topCenter;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
        return Alignment.bottomCenter;
    }
  }

  double _scaleFor(int i, double slot) {
    final p = _ptr;
    if (p == null) return 1;
    final c = i * slot + slot / 2;
    final d = (p - c).abs() / slot;
    final k = math.max(0.0, 1 - d / 2.2);
    return 1 + (st.dockZoom - 1) * k * k * (3 - 2 * k);
  }

  Widget _icon(Map<String, dynamic> it, double size) {
    final icon = (it['icon'] ?? '') as String;
    final path = (it['path'] ?? '') as String;
    if (icon.isNotEmpty && File(icon).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(size * 0.2), child: Image.file(File(icon), width: size, height: size, fit: BoxFit.cover));
    }
    final isDir = path.isNotEmpty && FileSystemEntity.isDirectorySync(path);
    final name = ((it['name'] ?? '?') as String);
    final hue = (name.hashCode % 360).abs().toDouble();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(1, hue, 0.55, 0.5).toColor(),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: isDir
          ? Icon(Icons.folder, color: Colors.white, size: size * 0.6)
          : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _addItem() async {
    final r = await FilePicker.platform.pickFiles();
    final path = r?.files.single.path;
    if (path == null) return;
    final base = path.split(RegExp(r'[\\/]')).last;
    final name = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    st.dockItems = [...st.dockItems, {'name': name, 'path': path, 'icon': ''}];
    await widget.store.saveSettings(touch: false);
    if (mounted) setState(() {});
  }

  void _menu(Offset global, {int? index}) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(global);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(local.dx, local.dy, box.size.width - local.dx, box.size.height - local.dy),
      items: [
        if (index != null) const PopupMenuItem(value: 'run', child: Text('Запустить')),
        if (index != null) const PopupMenuItem(value: 'del', child: Text('Убрать из дока')),
        const PopupMenuItem(value: 'add', child: Text('Добавить программу или файл…')),
        const PopupMenuItem(value: 'exit', child: Text('Выйти из режима дока')),
      ],
    ).then((v) async {
      if (v == 'run' && index != null) {
        DockMode.launch((st.dockItems[index]['path'] ?? '') as String);
      } else if (v == 'del' && index != null) {
        st.dockItems = [...st.dockItems]..removeAt(index);
        await widget.store.saveSettings(touch: false);
        if (mounted) setState(() {});
      } else if (v == 'add') {
        await _addItem();
      } else if (v == 'exit') {
        await DockMode.exit();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = st.dockSize.toDouble();
    final slot = size + 14;
    final items = st.dockItems;
    final dark = Pal.dark(context);
    final bg = (dark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF)).withOpacity(st.dockOpacity.clamp(0.2, 1.0));
    Widget cell(int i) {
      final s = _scaleFor(i, slot);
      final it = items[i];
      return SizedBox(
        width: _horiz ? slot : size + 14,
        height: _horiz ? size + 14 : slot,
        child: Center(
          child: Transform.scale(
            scale: s,
            alignment: _anchor,
            child: GestureDetector(
              onTap: () => DockMode.launch((it['path'] ?? '') as String),
              onSecondaryTapUp: (d) => _menu(d.globalPosition, index: i),
              child: Tooltip(message: (it['name'] ?? '') as String, child: _icon(it, size)),
            ),
          ),
        ),
      );
    }

    final cells = [for (var i = 0; i < items.length; i++) cell(i)];
    final strip = items.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Док пуст: правая кнопка → «Добавить»', style: TextStyle(color: Pal.secondary(context))),
          )
        : MouseRegion(
            onHover: (e) => setState(() => _ptr = _horiz ? e.localPosition.dx : e.localPosition.dy),
            onExit: (_) => setState(() => _ptr = null),
            child: _horiz ? Row(mainAxisSize: MainAxisSize.min, children: cells) : Column(mainAxisSize: MainAxisSize.min, children: cells),
          );
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        onPanStart: (_) => windowManager.startDragging(),
        child: Align(
          alignment: _anchor,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Pal.border(context)),
            ),
            child: strip,
          ),
        ),
      ),
    );
  }
}

/// Раздел «Док» в приложении: настройки панели, список значков, запуск режима дока.
class DockPage extends StatefulWidget {
  final Store store;
  const DockPage({super.key, required this.store});
  @override
  State<DockPage> createState() => _DockPageState();
}
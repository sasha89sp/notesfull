import 'package:flutter/material.dart';
import 'store.dart';
import 'widgets.dart';

/// Один блок трёхблочного вида.
class PaneSpec {
  final String title;
  final Widget child;
  const PaneSpec(this.title, this.child);
}

/// Три блока: «side» (папки/категории), «list» (список), «detail» (редактор).
/// Ширину боковых блоков можно менять мышью, порядок блоков — стрелками в заголовке.
/// Настройки хранятся в профиле (paneOrder, paneW).
class ThreePane extends StatefulWidget {
  final Store store;
  final Map<String, PaneSpec> panes;
  const ThreePane({super.key, required this.store, required this.panes});

  @override
  State<ThreePane> createState() => _ThreePaneState();
}

class _ThreePaneState extends State<ThreePane> {
  Store get s => widget.store;

  List<String> get _order {
    final o = [for (final k in s.settings.paneOrder) if (widget.panes.containsKey(k)) k];
    for (final k in widget.panes.keys) {
      if (!o.contains(k)) o.add(k);
    }
    return o;
  }

  double _w(String k) => (s.settings.paneW[k] ?? (k == 'side' ? 230 : 330)).clamp(150.0, 700.0);

  void _move(String k, int d) {
    final o = _order;
    final i = o.indexOf(k);
    final j = i + d;
    if (j < 0 || j >= o.length) return;
    o[i] = o[j];
    o[j] = k;
    s.settings.paneOrder = o;
    s.saveSettings();
    setState(() {});
  }

  void _drag(List<String> o, int divider, double dx) {
    // двигаем границу: меняем ширину бокового блока рядом с разделителем
    final left = o[divider], right = o[divider + 1];
    setState(() {
      if (left != 'detail') {
        s.settings.paneW[left] = (_w(left) + dx).clamp(150.0, 700.0);
      } else if (right != 'detail') {
        s.settings.paneW[right] = (_w(right) - dx).clamp(150.0, 700.0);
      }
    });
  }

  Widget _header(String k, PaneSpec p, bool first, bool last) {
    final sec = Pal.secondary(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Pal.border(context), width: 0.5))),
      child: Row(children: [
        Expanded(
            child: Text(p.title.toUpperCase(),
                style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, color: sec, fontWeight: FontWeight.w600))),
        _arrow(Icons.chevron_left, first ? null : () => _move(k, -1), 'Блок влево'),
        _arrow(Icons.chevron_right, last ? null : () => _move(k, 1), 'Блок вправо'),
      ]),
    );
  }

  Widget _arrow(IconData i, VoidCallback? f, String tip) => SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 16,
            tooltip: tip,
            onPressed: f,
            icon: Icon(i)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var o = _order;
      // в узком окне боковой блок скрывается
      if (c.maxWidth < 760) o = o.where((k) => k != 'side').toList();
      final kids = <Widget>[];
      for (var i = 0; i < o.length; i++) {
        final k = o[i];
        final p = widget.panes[k]!;
        final body = Column(children: [
          _header(k, p, i == 0, i == o.length - 1),
          Expanded(child: ClipRect(child: p.child)),
        ]);
        kids.add(k == 'detail' ? Expanded(child: body) : SizedBox(width: _w(k), child: body));
        if (i < o.length - 1) {
          final idx = i;
          kids.add(MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => _drag(o, idx, d.delta.dx),
              onHorizontalDragEnd: (_) => s.saveSettings(),
              child: Container(
                width: 6,
                alignment: Alignment.center,
                child: Container(width: 1, color: Pal.border(context)),
              ),
            ),
          ));
        }
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
    });
  }
}

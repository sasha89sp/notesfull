import 'package:flutter/material.dart';

/// Пункт контекстного меню (правая кнопка мыши / долгое нажатие).
class CtxItem {
  final String id;
  final String label;
  final IconData? icon;
  final bool danger;
  const CtxItem(this.id, this.label, {this.icon, this.danger = false});
}

/// Показывает меню в точке [pos] и возвращает id выбранного пункта.
/// Пункт с id '-' — разделитель.
Future<String?> showCtx(BuildContext context, Offset pos, List<CtxItem> items) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final err = Theme.of(context).colorScheme.error;
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      for (final i in items)
        if (i.id == '-')
          const PopupMenuDivider(height: 6)
        else
          PopupMenuItem<String>(
            value: i.id,
            height: 34,
            child: Row(children: [
              if (i.icon != null) Icon(i.icon, size: 16, color: i.danger ? err : null),
              if (i.icon != null) const SizedBox(width: 10),
              Text(i.label, style: TextStyle(fontSize: 13, color: i.danger ? err : null)),
            ]),
          ),
    ],
  );
}

/// Область с контекстным меню: правая кнопка мыши и долгое нажатие.
class CtxArea extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPos) onMenu;
  const CtxArea({super.key, required this.child, required this.onMenu, this.onTap, this.onDoubleTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      onLongPressStart: (d) => onMenu(d.globalPosition),
      child: child,
    );
  }
}

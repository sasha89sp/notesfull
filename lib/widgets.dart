import 'package:flutter/material.dart';
import 'theme.dart';

class Pal {
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static AppColors _c(BuildContext c) => AppColors.of(Theme.of(c).brightness);
  static Color border(BuildContext c) => _c(c).divider;
  static Color card(BuildContext c) => _c(c).panel;
  static Color card3(BuildContext c) => _c(c).sidebar;
  static Color secondary(BuildContext c) => _c(c).text2;
  static Color muted(BuildContext c) => _c(c).muted;
  static Color accent(BuildContext c) => _c(c).accent;
  static Color sidebar(BuildContext c) => _c(c).sidebar;
  static Color panel(BuildContext c) => _c(c).panel;
  static Color hover(BuildContext c) => _c(c).hover;
  static Color tagFg(BuildContext c) => _c(c).tagFg;
  static Color tagBg(BuildContext c) => _c(c).tagBg;
  static Color linkBg(BuildContext c) => _c(c).linkBg;
  static Color success(BuildContext c) =>
      dark(c) ? const Color(0xFF34D399) : const Color(0xFF059669);
  static Color warn(BuildContext c) =>
      dark(c) ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  static Color error(BuildContext c) =>
      dark(c) ? const Color(0xFFF87171) : const Color(0xFFDC2626);
}

const List<int> kTagColors = [
  0xFFFF3B30, 0xFFFF9500, 0xFF34C759, 0xFF007AFF, 0xFF5856D6, 0xFFAF52DE, 0xFF00C7BE,
];

Color tagColor(String tag) {
  var h = 0;
  for (final c in tag.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return Color(kTagColors[h % kTagColors.length]);
}

/// Карточка: скругление 10, тонкая граница, едва заметная тень.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Pal.card(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Pal.border(context)),
        boxShadow: Pal.dark(context)
            ? null
            : const [BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      );
}

class Hint extends StatelessWidget {
  final String text;
  const Hint(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(color: Pal.secondary(context), fontSize: 13)),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final int color;
  final double radius;
  const Avatar(this.name, this.color, {super.key, this.radius = 18});
  @override
  Widget build(BuildContext context) {
    final ch = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(color),
      child: Text(ch,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: radius * 0.9)),
    );
  }
}

class TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  const TagChip(this.tag, {super.key, this.onDelete, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = Pal.tagFg(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Pal.tagBg(context),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('#$tag', style: TextStyle(color: c, fontSize: 12.5)),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              InkWell(
                  onTap: onDelete,
                  child: Icon(Icons.close, size: 14, color: c)),
            ],
          ]),
        ),
      ),
    );
  }
}

class Fab extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  const Fab({super.key, required this.onPressed, this.icon = Icons.add});
  @override
  Widget build(BuildContext context) => Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(onPressed: onPressed, child: Icon(icon)),
      );
}

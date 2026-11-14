import 'package:flutter/material.dart';

class Pal {
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color border(BuildContext c) =>
      dark(c) ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  static Color card(BuildContext c) =>
      dark(c) ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  static Color card3(BuildContext c) =>
      dark(c) ? const Color(0xFF27272A) : const Color(0xFFF4F4F5);
  static Color secondary(BuildContext c) => dark(c) ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
  static Color success(BuildContext c) =>
      dark(c) ? const Color(0xFF4ADE80) : const Color(0xFF059669);
  static Color warn(BuildContext c) =>
      dark(c) ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  static Color error(BuildContext c) =>
      dark(c) ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
}

const List<int> kTagColors = [
  0xFFD97706, 0xFF4F46E5, 0xFF059669, 0xFF2563EB, 0xFF9333EA, 0xFFDB2777, 0xFF0891B2,
];

Color tagColor(String tag) {
  var h = 0;
  for (final c in tag.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return Color(kTagColors[h % kTagColors.length]);
}

/// Унифицированная карточка приложения в стиле NotePlan.
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
        border: Border.all(color: Pal.border(context), width: 0.7),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(.045),
          splashColor: Theme.of(context).colorScheme.primary.withOpacity(.08),
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
    final c = tagColor(tag);
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('#$tag', style: TextStyle(color: c, fontSize: 13)),
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

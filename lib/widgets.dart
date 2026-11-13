import 'package:flutter/material.dart';

class Pal {
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color border(BuildContext c) =>
      dark(c) ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);
  static Color card(BuildContext c) =>
      dark(c) ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
  static Color card3(BuildContext c) =>
      dark(c) ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
  static Color secondary(BuildContext c) => const Color(0xFF8E8E93);
  static Color success(BuildContext c) =>
      dark(c) ? const Color(0xFF30D158) : const Color(0xFF34C759);
  static Color warn(BuildContext c) =>
      dark(c) ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  static Color error(BuildContext c) =>
      dark(c) ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
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

/// Карточка в стиле Apple: скругление 12, граница 0.5, без теней.
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.border(context), width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
    final c = tagColor(tag);
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: c.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
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

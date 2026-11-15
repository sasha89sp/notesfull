part of 'schedule_panel.dart';


class _EventCardState extends State<_EventCard> {
  bool _hover = false;

  (Color, Color) _colors(bool dark) {
    final e = widget.event;
    if (Cals.idOf(e) != 'main') {
      final c = Cals.color(widget.store.settings, e);
      return (c.withOpacity(dark ? 0.20 : 0.14), c);
    }
    final Color strong = e.isTask
        ? const Color(0xFF059669)
        : e.allDay
            ? const Color(0xFFEA580C)
            : const Color(0xFF2563EB);
    final bg = dark
        ? strong.withOpacity(0.20)
        : e.isTask
            ? const Color(0xFFD1FAE5)
            : e.allDay
                ? const Color(0xFFFFEDD5)
                : const Color(0xFFDBEAFE);
    return (bg, strong);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final dark = Pal.dark(context);
    final (bg, strong) = _colors(dark);
    final time = e.allDay
        ? 'весь день'
        : e.isTask
            ? fmtTime(e.startDt)
            : '${fmtTime(e.startDt)} – ${fmtTime(e.endDt)}';
    final tc = dark ? const Color(0xFFFAFAFA) : const Color(0xFF1E293B);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.01 : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: strong, width: 3)),
            boxShadow: _hover ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))] : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.isTask)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 1),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Checkbox(
                        value: e.done,
                        onChanged: (v) {
                          e.done = v ?? false;
                          e.updatedAt = nowMs();
                          widget.store.eventsChanged();
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title.isEmpty ? 'Без названия' : e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: e.done ? Pal.muted(context) : tc,
                            decoration: e.done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 2),
                    Text(time,
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Pal.secondary(context))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
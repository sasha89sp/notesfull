import 'dart:async';
import 'package:flutter/material.dart';
import 'remote.dart';
import 'store.dart';
import 'widgets.dart';

/// Глобальная строка статуса синхронизации: видна на любом экране (в том числе
/// в настройках). Процент, скорость ↓/↑, этап; нажатие открывает журнал.
class StatusStrip extends StatefulWidget {
  final Store store;
  final VoidCallback onOpen;
  final bool compact;
  const StatusStrip({super.key, required this.store, required this.onOpen, this.compact = false});

  /// Показывается ли строка сейчас (нужно, чтобы убрать нижний отступ у содержимого).
  static bool visible(Store s) => s.syncing || s.lastSync != null;

  @override
  State<StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<StatusStrip> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.store.syncing && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (!StatusStrip.visible(s)) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sec = Pal.secondary(context);
    String text;
    Color col = sec;
    if (s.syncing) {
      final p = s.progress;
      final pc = p == null ? '' : '${(p * 100).round()}% · ';
      final (u, d) = Net.speed();
      text = '$pc↓${Net.fmtSpeed(d)} ↑${Net.fmtSpeed(u)} · ${s.progressText}';
    } else {
      final last = s.lastSync!;
      text = last.status == 'ok' ? 'Синхронизировано ${last.when}' : last.statusText;
      if (last.status != 'ok' && last.status != 'cancelled') col = Pal.error(context);
    }
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Material(
      color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (s.syncing)
            LinearProgressIndicator(minHeight: 2, value: s.progress),
          InkWell(
            onTap: widget.onOpen,
            child: SizedBox(
              height: widget.compact ? 22 : 26,
              child: Row(children: [
                const SizedBox(width: 10),
                Icon(s.syncing ? Icons.sync : Icons.check_circle_outline, size: 13, color: col),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: col))),
                if (s.syncing)
                  InkWell(
                      onTap: s.cancelSync,
                      child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.stop_circle_outlined, size: 16)))
                else
                  InkWell(
                      onTap: s.syncAll,
                      child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.sync, size: 16))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

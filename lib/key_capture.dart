// ▸ Захват нажатых клавиш (диалог «нажмите клавиши…») и перевод в коды Windows VK
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'win_module.dart' show kKeyNames;

/// Код VK по логической клавише Flutter (null — неизвестная клавиша).
int? vkOf(LogicalKeyboardKey k) {
  final fixed = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.shiftLeft: 0xA0, LogicalKeyboardKey.shiftRight: 0xA1,
    LogicalKeyboardKey.controlLeft: 0xA2, LogicalKeyboardKey.controlRight: 0xA3,
    LogicalKeyboardKey.altLeft: 0xA4, LogicalKeyboardKey.altRight: 0xA5,
    LogicalKeyboardKey.metaLeft: 0x5B, LogicalKeyboardKey.metaRight: 0x5C,
    LogicalKeyboardKey.capsLock: 0x14, LogicalKeyboardKey.tab: 0x09, LogicalKeyboardKey.escape: 0x1B,
    LogicalKeyboardKey.space: 0x20, LogicalKeyboardKey.enter: 0x0D, LogicalKeyboardKey.backspace: 0x08,
    LogicalKeyboardKey.delete: 0x2E, LogicalKeyboardKey.insert: 0x2D, LogicalKeyboardKey.home: 0x24,
    LogicalKeyboardKey.end: 0x23, LogicalKeyboardKey.pageUp: 0x21, LogicalKeyboardKey.pageDown: 0x22,
    LogicalKeyboardKey.arrowLeft: 0x25, LogicalKeyboardKey.arrowUp: 0x26,
    LogicalKeyboardKey.arrowRight: 0x27, LogicalKeyboardKey.arrowDown: 0x28,
    LogicalKeyboardKey.pause: 0x13, LogicalKeyboardKey.scrollLock: 0x91, LogicalKeyboardKey.contextMenu: 0x5D,
    LogicalKeyboardKey.semicolon: 0xBA, LogicalKeyboardKey.equal: 0xBB, LogicalKeyboardKey.comma: 0xBC,
    LogicalKeyboardKey.minus: 0xBD, LogicalKeyboardKey.period: 0xBE, LogicalKeyboardKey.slash: 0xBF,
    LogicalKeyboardKey.backquote: 0xC0, LogicalKeyboardKey.bracketLeft: 0xDB,
    LogicalKeyboardKey.backslash: 0xDC, LogicalKeyboardKey.bracketRight: 0xDD, LogicalKeyboardKey.quote: 0xDE,
  };
  final f = fixed[k];
  if (f != null) return f;
  final fn = [
    LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3, LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5, LogicalKeyboardKey.f6, LogicalKeyboardKey.f7, LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9, LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
  ].indexOf(k);
  if (fn >= 0) return 0x70 + fn;
  final id = k.keyId;
  if (id >= 0x61 && id <= 0x7a) return id - 0x20; // буквы a–z → 'A'–'Z'
  if (id >= 0x30 && id <= 0x39) return id; // цифры
  return null;
}

String keyName(int vk) => kKeyNames[vk] ?? 'VK 0x${vk.toRadixString(16).toUpperCase()}';

String comboText(List<int> vks) => vks.isEmpty ? '—' : vks.map(keyName).join(' + ');

/// Диалог: пользователь нажимает клавишу/комбинацию, подтверждает кнопкой.
/// [single] — нужна одна клавиша. Возвращает список VK или null при отмене.
Future<List<int>?> captureKeys(BuildContext context, {required String title, bool single = false}) {
  return showDialog<List<int>>(context: context, builder: (_) => _CaptureDialog(title: title, single: single));
}

class _CaptureDialog extends StatefulWidget {
  final String title;
  final bool single;
  const _CaptureDialog({required this.title, required this.single});
  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  final Set<int> _down = {};
  List<int> _rec = [];

  KeyEventResult _key(FocusNode n, KeyEvent e) {
    final vk = vkOf(e.logicalKey);
    if (vk == null) return KeyEventResult.handled;
    if (e is KeyDownEvent) {
      setState(() {
        if (_down.isEmpty) _rec = []; // новая попытка после отпускания всех клавиш
        _down.add(vk);
        if (!_rec.contains(vk)) _rec = [..._rec, vk];
        if (widget.single) _rec = [vk];
      });
    } else if (e is KeyUpEvent) {
      setState(() => _down.remove(vk));
    }
    return KeyEventResult.handled; // не даём клавишам действовать в самом приложении
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.single ? 'Нажмите нужную клавишу на клавиатуре.' : 'Нажмите клавишу или сочетание клавиш на клавиатуре.'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
              child: Text(_rec.isEmpty ? 'Жду нажатия…' : comboText(_rec),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(onPressed: _rec.isEmpty ? null : () => setState(() { _rec = []; _down.clear(); }), child: const Text('Заново')),
        FilledButton(onPressed: _rec.isEmpty ? null : () => Navigator.pop(context, _rec), child: const Text('Подтвердить')),
      ],
    );
  }
}

// ▸ Модуль «Диктовка»: зажмите кнопку (или нажмите для переключения), наговорите — текст
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dictation.dart';
import 'models.dart';
import 'store.dart';
import 'winsys.dart';
import 'widgets.dart';

/// Модуль «Диктовка»: зажмите кнопку (или нажмите для переключения), наговорите — текст
/// расшифруется и сразу попадёт в буфер обмена, чтобы вставить его в любое приложение.
/// В Windows можно включить глобальную комбинацию клавиш (модуль «Windows»).
class VoicePage extends StatefulWidget {
  final Store store;
  const VoicePage({super.key, required this.store});
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final _text = TextEditingController();
  String _seen = '';

  Dictation get d => Dictation.I;

  @override
  void initState() {
    super.initState();
    d.store = widget.store;
    _text.text = d.text;
    _seen = d.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) {
        if (d.text != _seen) {
          _seen = d.text;
          _text.text = d.text;
        }
        final acc = Pal.accent(context);
        final sec = Pal.secondary(context);
        final secs = d.sw.elapsed.inSeconds;
        final red = const Color(0xFFDC2626);
        return ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: GestureDetector(
              onLongPressStart: (_) => d.start(),
              onLongPressEnd: (_) => d.stop(),
              onTap: () => d.recording ? d.stop() : d.start(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d.recording ? red : acc,
                  boxShadow: [BoxShadow(color: (d.recording ? red : acc).withOpacity(0.3), blurRadius: d.recording ? 24 : 10)],
                ),
                child: Icon(d.busy ? Icons.hourglass_top : (d.recording ? Icons.stop : Icons.mic), size: 48, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
                d.recording ? '${two(secs ~/ 60)}:${two(secs % 60)}' : 'Зажмите и говорите, или нажмите для переключения',
                style: TextStyle(color: sec)),
          ),
          if (d.status.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Center(child: Text(d.status, style: TextStyle(color: sec, fontSize: 13)))),
          if (WinSys.available && widget.store.settings.dictGlobal)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(child: Text('Глобальная комбинация включена (модуль «Windows»)', style: TextStyle(color: Pal.muted(context), fontSize: 12))),
            ),
          const SizedBox(height: 18),
          TextField(
            controller: _text,
            maxLines: null,
            minLines: 4,
            onChanged: d.setText,
            decoration: const InputDecoration(labelText: 'Текст (можно поправить)', alignLabelWithHint: true),
          ),
          Row(children: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: _text.text)),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Копировать'),
            ),
            TextButton.icon(
              onPressed: () {
                d.setText('');
                _text.clear();
              },
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Очистить'),
            ),
          ]),
          if (d.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('ПОСЛЕДНИЕ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Pal.muted(context))),
            for (final h in d.history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  d.setText(h);
                  _text.text = h;
                  Clipboard.setData(ClipboardData(text: h));
                },
              ),
          ],
        ]);
      },
    );
  }
}

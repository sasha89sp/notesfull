import 'dart:io';
import 'package:flutter/material.dart';
import 'dictation.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'winsys.dart';

/// Таблица клавиш для правил: код VK → название.
final Map<int, String> kKeyNames = () {
  final m = <int, String>{
    0xA0: 'Левый Shift', 0xA1: 'Правый Shift', 0xA2: 'Левый Ctrl', 0xA3: 'Правый Ctrl',
    0xA4: 'Левый Alt', 0xA5: 'Правый Alt', 0x5B: 'Левый Win', 0x5C: 'Правый Win', 0x14: 'CapsLock',
    0x09: 'Tab', 0x1B: 'Esc', 0x20: 'Пробел', 0x0D: 'Enter', 0x08: 'Backspace', 0x2E: 'Delete',
    0x2D: 'Insert', 0x24: 'Home', 0x23: 'End', 0x21: 'PageUp', 0x22: 'PageDown',
    0x25: '←', 0x26: '↑', 0x27: '→', 0x28: '↓', 0x13: 'Pause', 0x91: 'ScrollLock', 0x5D: 'Меню',
  };
  for (var i = 0; i < 12; i++) {
    m[0x70 + i] = 'F${i + 1}';
  }
  for (var i = 0; i < 26; i++) {
    m[0x41 + i] = String.fromCharCode(0x41 + i);
  }
  for (var i = 0; i < 10; i++) {
    m[0x30 + i] = '$i';
  }
  return m;
}();

/// Применение настроек модуля «Windows» (при запуске и после изменений).
class WinService {
  static Future<String?> apply(Store s) async {
    final st = s.settings;
    Dictation.I.store = s;
    Dictation.I.applyGlobal();
    if (!WinSys.available || !Platform.isWindows) return null;
    if (!st.remapOn) {
      WinSys.stopRemap();
      return null;
    }
    final rules = <List<int>>[
      for (final r in st.remaps)
        if ((r['on'] ?? true) == true && r['from'] is int && (r['to'] as List).isNotEmpty)
          [r['from'] as int, for (final x in (r['to'] as List)) (x as num).toInt()],
    ];
    return WinSys.startRemap(rules);
  }
}

/// Модуль «Windows»: переназначение клавиш во всей системе и горячая клавиша диктовки.
class WinPage extends StatefulWidget {
  final Store store;
  const WinPage({super.key, required this.store});
  @override
  State<WinPage> createState() => _WinPageState();
}

class _WinPageState extends State<WinPage> {
  String _err = '';

  Settings get st => widget.store.settings;

  Future<void> _save() async {
    await widget.store.saveSettings(touch: false);
    final e = await WinService.apply(widget.store);
    if (mounted) setState(() => _err = e ?? '');
  }

  Widget _keyDrop(int? value, void Function(int?) set, {bool allowNone = false}) {
    return DropdownButton<int?>(
      value: kKeyNames.containsKey(value) ? value : null,
      isDense: true,
      hint: const Text('—'),
      items: [
        if (allowNone) const DropdownMenuItem<int?>(value: null, child: Text('—')),
        for (final k in kKeyNames.entries) DropdownMenuItem<int?>(value: k.key, child: Text(k.value)),
      ],
      onChanged: (v) {
        set(v);
        _save();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sec = Pal.secondary(context);
    final ok = WinSys.available && Platform.isWindows;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!ok)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
              Platform.isWindows
                  ? 'В этой сборке нет системных функций Windows (собрана версия без win32). Правила можно настроить, но они не будут работать.'
                  : 'Модуль работает только в Windows.',
              style: TextStyle(color: Pal.error(context))),
        ),
      if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err, style: TextStyle(color: Pal.error(context)))),
      const SectionTitle('Переназначение клавиш'),
      Hint('Нажатие выбранной клавиши заменяется комбинацией — во всей системе, пока ASRbox запущен. '
          'Пример: «Левый Shift» → Ctrl + C. Исходная клавиша перестаёт работать как раньше. '
          'Если что-то пошло не так, выключите переключатель ниже.'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Переназначение включено'),
        value: st.remapOn,
        onChanged: (v) {
          setState(() => st.remapOn = v);
          _save();
        },
      ),
      for (var i = 0; i < st.remaps.length; i++) _rule(i),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() => st.remaps = [
                  ...st.remaps,
                  {'from': 0xA0, 'to': [0xA2, 0x43], 'on': true},
                ]);
            _save();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Добавить правило'),
        ),
      ),
      const SectionTitle('Диктовка по горячей клавише'),
      Hint('Зажмите комбинацию в любом приложении и говорите; отпустите — расшифрованный текст окажется '
          'в буфере обмена (придёт уведомление). Нужен включённый модуль «Диктовка» с настроенной расшифровкой.'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Глобальная комбинация включена'),
        value: st.dictGlobal,
        onChanged: (v) {
          setState(() => st.dictGlobal = v);
          _save();
        },
      ),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Комбинация:', style: TextStyle(color: sec)),
        for (var i = 0; i < 3; i++)
          _keyDrop(i < st.dictKeys.length ? st.dictKeys[i] : null, (v) {
            final l = [...st.dictKeys];
            while (l.length < 3) {
              l.add(0);
            }
            l[i] = v ?? 0;
            setState(() => st.dictKeys = l.where((x) => x != 0).toList());
          }, allowNone: true),
      ]),
    ]);
  }

  Widget _rule(int i) {
    final r = st.remaps[i];
    final to = [for (final x in (r['to'] as List)) (x as num).toInt()];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Checkbox(
              value: (r['on'] ?? true) == true,
              onChanged: (v) {
                setState(() => r['on'] = v ?? true);
                _save();
              }),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _keyDrop(r['from'] as int?, (v) => setState(() => r['from'] = v ?? 0xA0)),
              const Icon(Icons.arrow_forward, size: 16),
              for (var k = 0; k < 3; k++)
                _keyDrop(k < to.length ? to[k] : null, (v) {
                  final l = [...to];
                  while (l.length < 3) {
                    l.add(0);
                  }
                  l[k] = v ?? 0;
                  setState(() => r['to'] = l.where((x) => x != 0).toList());
                }, allowNone: true),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () {
              setState(() => st.remaps = [...st.remaps]..removeAt(i));
              _save();
            },
          ),
        ]),
      ),
    );
  }
}

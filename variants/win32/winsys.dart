import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Системные функции Windows: состояние клавиш вне окна приложения и переназначение клавиш
/// низкоуровневым хуком клавиатуры (WH_KEYBOARD_LL) в отдельном изоляте.
class WinSys {
  static const bool available = true;

  static bool isDown(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

  static Isolate? _iso;
  static SendPort? _cmd;

  static Future<String?> startRemap(List<List<int>> rules) async {
    if (rules.isEmpty) {
      stopRemap();
      return null;
    }
    if (_iso != null) {
      _cmd?.send(rules);
      return null;
    }
    final rp = ReceivePort();
    final done = Completer<String?>();
    rp.listen((m) {
      if (m is SendPort) {
        _cmd = m;
      } else if (m == 'ok' && !done.isCompleted) {
        done.complete(null);
      } else if (m == 'error' && !done.isCompleted) {
        done.complete('Не удалось установить перехват клавиатуры');
      }
    });
    try {
      _iso = await Isolate.spawn(_entry, [rp.sendPort, rules]);
      return await done.future.timeout(const Duration(seconds: 4), onTimeout: () => 'Перехват клавиатуры не ответил');
    } catch (e) {
      _iso = null;
      return '$e';
    }
  }

  static void stopRemap() {
    _cmd?.send('stop');
    _cmd = null;
    _iso = null;
  }
}

// ----------------------------------------------------------------- изолят хука

const int _marker = 0x41535242; // «ASRB»: пометка собственных нажатий, чтобы не зациклиться
Map<int, List<int>> _map = {};
int _hook = 0;

Map<int, List<int>> _parse(List<dynamic> rules) {
  final m = <int, List<int>>{};
  for (final r in rules) {
    final l = [for (final x in (r as List)) x as int];
    if (l.length >= 2) m[l.first] = l.sublist(1);
  }
  return m;
}

void _send(List<int> vks, bool up) {
  final n = vks.length;
  final inputs = calloc<INPUT>(n);
  for (var i = 0; i < n; i++) {
    final inp = inputs[i];
    inp.type = INPUT_KEYBOARD;
    inp.ki.wVk = vks[i];
    inp.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    inp.ki.dwExtraInfo = _marker;
  }
  SendInput(n, inputs, sizeOf<INPUT>());
  calloc.free(inputs);
}

int _proc(int nCode, int wParam, int lParam) {
  if (nCode == HC_ACTION) {
    final kb = Pointer<KBDLLHOOKSTRUCT>.fromAddress(lParam).ref;
    if (kb.dwExtraInfo != _marker) {
      final to = _map[kb.vkCode];
      if (to != null) {
        if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
          _send(to, false);
          return 1; // исходное нажатие поглощено
        }
        if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
          _send(to.reversed.toList(), true);
          return 1;
        }
      }
    }
  }
  return CallNextHookEx(_hook, nCode, wParam, lParam);
}

Future<void> _entry(List<Object> args) async {
  final reply = args[0] as SendPort;
  final cmd = ReceivePort();
  reply.send(cmd.sendPort);
  _map = _parse(args[1] as List);
  var running = true;
  cmd.listen((m) {
    if (m == 'stop') {
      running = false;
    } else if (m is List) {
      _map = _parse(m);
    }
  });
  _hook = SetWindowsHookEx(WH_KEYBOARD_LL, Pointer.fromFunction<HOOKPROC>(_proc, 0), GetModuleHandle(nullptr), 0);
  if (_hook == 0) {
    reply.send('error');
    return;
  }
  reply.send('ok');
  final msg = calloc<MSG>();
  while (running) {
    while (PeekMessage(msg, 0, 0, 0, PM_REMOVE) != 0) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
    await Future<void>.delayed(const Duration(milliseconds: 6));
  }
  UnhookWindowsHookEx(_hook);
  calloc.free(msg);
}

// ▸ Диктовка: запись → расшифровка → буфер обмена. Используется страницей «Диктовка» и
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'local_tx.dart';
import 'models.dart';
import 'notify.dart';
import 'store.dart';
import 'transcribe.dart';
import 'winsys.dart';

/// Диктовка: запись → расшифровка → буфер обмена. Используется страницей «Диктовка» и
/// (в Windows) глобальной горячей клавишей: зажали комбинацию — говорите, отпустили — текст в буфере.
class Dictation extends ChangeNotifier {
  static final Dictation I = Dictation();

  Store? store;
  AudioRecorder? _rec;
  final Stopwatch sw = Stopwatch();
  Timer? _tick, _poll;
  bool recording = false, busy = false;
  String status = '';
  String text = '';
  final List<String> history = [];
  bool _fromHotkey = false, _held = false;

  Settings? get st => store?.settings;

  String _mode() {
    final m = st?.txMode ?? 'api';
    if (m == 'off') return 'off';
    if (m == 'local' && LocalTx.available) return 'local';
    if (m == 'api') return 'api';
    return LocalTx.available ? 'local' : 'api';
  }

  Future<void> start({bool hotkey = false}) async {
    if (recording || busy || st == null) return;
    _fromHotkey = hotkey;
    try {
      _rec ??= AudioRecorder();
      if (!await _rec!.hasPermission()) {
        status = 'Нет доступа к микрофону';
        notifyListeners();
        return;
      }
      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}dict_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _rec!.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
      sw
        ..reset()
        ..start();
      _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners());
      recording = true;
      status = 'Запись…';
    } catch (e) {
      status = 'Не удалось начать запись: $e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!recording) return;
    _tick?.cancel();
    sw.stop();
    recording = false;
    busy = true;
    status = 'Расшифровка…';
    notifyListeners();
    String? path;
    try {
      path = await _rec!.stop();
      if (path == null) throw 'Запись не получена';
      if (sw.elapsedMilliseconds < 400) throw 'Слишком короткая запись';
      final mode = _mode();
      if (mode == 'off') throw 'Расшифровка выключена (Настройки → Голос)';
      final String t;
      if (mode == 'local') {
        t = await LocalTx.transcribe(path, st!.txLocalModel, st!.txLang)
            .timeout(const Duration(minutes: 10), onTimeout: () => throw 'Расшифровка не завершилась за 10 минут');
      } else {
        t = await Transcriber.run(st!, await File(path).readAsBytes(), 'voice.wav');
      }
      text = t;
      await Clipboard.setData(ClipboardData(text: t));
      if (t.isNotEmpty) {
        history.insert(0, t);
        if (history.length > 20) history.removeLast();
      }
      status = t.isEmpty ? 'Речь не распознана' : 'Скопировано в буфер обмена';
      if (_fromHotkey && t.isNotEmpty) {
        Notifier.I.notifyNew('Диктовка: скопировано', t.length > 120 ? '${t.substring(0, 120)}…' : t);
      }
    } catch (e) {
      status = 'Ошибка: $e';
      if (_fromHotkey) Notifier.I.notifyNew('Диктовка', status);
    } finally {
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      busy = false;
      notifyListeners();
    }
  }

  void setText(String t) {
    text = t;
  }

  /// Включает/выключает глобальную горячую клавишу согласно настройкам (только Windows-сборка).
  void applyGlobal() {
    _poll?.cancel();
    _poll = null;
    final s = st;
    if (s == null || !WinSys.available || !s.dictGlobal || s.dictKeys.isEmpty) return;
    _poll = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final all = s.dictKeys.every(WinSys.isDown);
      if (all && !_held) {
        _held = true;
        start(hotkey: true);
      } else if (!all && _held) {
        _held = false;
        stop();
      }
    });
  }
}

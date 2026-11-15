import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'applog.dart';
import 'local_tx.dart';
import 'models.dart';
import 'remote.dart';
import 'widgets.dart';

/// Собственная загрузка моделей Whisper (ggml): с прогрессом, отменой, докачкой
/// и выбором источника. Файл кладётся туда, где его ищет пакет whisper_ggml
/// (каталог приложения, имя «ggml-<модель>.bin»), поэтому плагин находит модель и не качает её сам.
class ModelDl {
  static const sizes = {'tiny': 77691713, 'base': 147951465, 'small': 487601967};

  static String url(String model, String src) {
    final host = src == 'mirror' ? 'https://hf-mirror.com' : 'https://huggingface.co';
    return '$host/ggerganov/whisper.cpp/resolve/main/ggml-$model.bin';
  }

  /// Каталоги, где пакет может искать модель.
  static Future<List<String>> dirs() async {
    final out = <String>[];
    try {
      out.add((await getApplicationSupportDirectory()).path);
    } catch (_) {}
    try {
      final l = (await getLibraryDirectory()).path;
      if (!out.contains(l)) out.add(l);
    } catch (_) {}
    return out;
  }

  static String _file(String dir, String model) => '$dir${Platform.pathSeparator}ggml-$model.bin';

  /// Размер скачанной модели (0 — нет или файл неполный).
  static Future<int> have(String model) async {
    for (final d in await dirs()) {
      final f = File(_file(d, model));
      if (f.existsSync()) {
        final n = f.lengthSync();
        if (n >= (sizes[model] ?? 0) * 0.95) return n;
      }
    }
    return 0;
  }

  static Future<void> remove(String model) async {
    for (final d in await dirs()) {
      for (final p in [_file(d, model), '${_file(d, model)}.part']) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }
  }

  static bool cancelled = false;

  /// Скачивание с докачкой. [onProgress] получает (получено, всего).
  static Future<void> download(String model, String src, void Function(int, int) onProgress) async {
    cancelled = false;
    final ds = await dirs();
    if (ds.isEmpty) throw 'Не найден каталог приложения для модели';
    final target = _file(ds.first, model);
    final part = File('$target.part');
    final client = http.Client();
    try {
      var have = part.existsSync() ? part.lengthSync() : 0;
      final req = http.Request('GET', Uri.parse(url(model, src)));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 416) {
        // докачивать нечего или файл повреждён — начинаем заново
        part.deleteSync();
        have = 0;
        throw 'Сервер отклонил докачку, нажмите «Скачать» ещё раз';
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw 'Сервер ответил ${resp.statusCode}';
      }
      if (resp.statusCode == 200) have = 0; // сервер не поддерживает докачку
      final total = have + (resp.contentLength ?? (sizes[model] ?? 0) - have);
      final sink = part.openSync(mode: have > 0 ? FileMode.append : FileMode.write);
      var got = have;
      var last = 0;
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 45))) {
          if (cancelled) throw 'Загрузка отменена';
          sink.writeFromSync(chunk);
          got += chunk.length;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - last > 250) {
            last = now;
            onProgress(got, total);
          }
        }
      } finally {
        sink.closeSync();
      }
      if (got < (sizes[model] ?? 0) * 0.95) throw 'Файл скачан не полностью ($got Б), повторите';
      try {
        File(target).deleteSync();
      } catch (_) {}
      part.renameSync(target);
      for (final d in ds.skip(1)) {
        try {
          File(target).copySync(_file(d, model));
        } catch (_) {}
      }
      onProgress(got, got);
      AppLog.I.i('tx', 'Модель $model скачана ($got Б, $src)');
    } finally {
      client.close();
    }
  }
}

/// Блок «Модель Whisper» в настройках голоса: состояние, источник, скачать/отменить/удалить.
class ModelBox extends StatefulWidget {
  final Settings st;
  final VoidCallback onChanged;
  const ModelBox({super.key, required this.st, required this.onChanged});
  @override
  State<ModelBox> createState() => _ModelBoxState();
}

class _ModelBoxState extends State<ModelBox> {
  int _have = 0;
  bool _busy = false;
  double? _p;
  String _msg = '';
  String _model = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final m = widget.st.txLocalModel;
    final n = await ModelDl.have(m);
    if (mounted) setState(() {
      _have = n;
      _model = m;
    });
  }

  Future<void> _download() async {
    final st = widget.st;
    final m = st.txLocalModel;
    setState(() {
      _busy = true;
      _p = 0;
      _msg = 'Подключение…';
    });
    try {
      await ModelDl.download(m, st.txModelSrc, (got, total) {
        if (!mounted) return;
        setState(() {
          _p = total > 0 ? got / total : null;
          _msg = '${Net.fmtSize(got)} из ${Net.fmtSize(total)}';
        });
      });
      _msg = 'Модель скачана';
    } catch (e) {
      _msg = 'Ошибка: $e';
      AppLog.I.i('tx', 'Загрузка модели: $e');
    }
    _busy = false;
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (!LocalTx.available) return const SizedBox.shrink();
    final st = widget.st;
    if (_model != st.txLocalModel && !_busy) {
      Future<void>.microtask(_check);
    }
    final ok = _have > 0 && _model == st.txLocalModel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(ok ? 'Модель скачана (${Net.fmtSize(_have)})' : 'Модель не скачана')),
        Icon(ok ? Icons.check_circle : Icons.cloud_download_outlined,
            size: 18, color: ok ? Pal.success(context) : Pal.muted(context)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        const Expanded(child: Text('Источник')),
        DropdownButton<String>(
          value: st.txModelSrc,
          items: const [
            DropdownMenuItem(value: 'hf', child: Text('huggingface.co')),
            DropdownMenuItem(value: 'mirror', child: Text('hf-mirror.com (зеркало)')),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() => st.txModelSrc = v);
                  widget.onChanged();
                },
        ),
      ]),
      if (_busy) ...[
        LinearProgressIndicator(value: _p),
        const SizedBox(height: 4),
      ],
      if (_msg.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_msg, style: TextStyle(fontSize: 12, color: Pal.secondary(context)))),
      Wrap(spacing: 8, children: [
        if (_busy)
          OutlinedButton(onPressed: () => ModelDl.cancelled = true, child: const Text('Отмена'))
        else ...[
          if (!ok)
            OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Скачать')),
          if (ok || _msg.isNotEmpty)
            OutlinedButton(
                onPressed: () async {
                  await ModelDl.remove(st.txLocalModel);
                  _msg = '';
                  await _check();
                },
                child: Text(ok ? 'Удалить' : 'Сбросить загрузку')),
        ],
      ]),
      const SizedBox(height: 8),
    ]);
  }
}

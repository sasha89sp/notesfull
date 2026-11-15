import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel nativeChannel = MethodChannel('mysecure/native');

/// FLAG_SECURE на Android (запрет скриншотов).
Future<void> setSecure(bool on) async {
  if (!Platform.isAndroid) return;
  try {
    await nativeChannel.invokeMethod<void>('secure', on);
  } catch (_) {}
}

bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Надёжная запись: данные сначала целиком попадают во временный файл,
/// предыдущая версия сохраняется как «.bak», затем файл подменяется.
/// При сбое питания остаётся либо старая, либо новая версия.
Future<void> writeAtomic(File f, List<int> bytes) async {
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  if (await f.exists()) {
    final bak = File('${f.path}.bak');
    try {
      if (await bak.exists()) await bak.delete();
      await f.rename(bak.path);
    } catch (_) {}
  }
  await tmp.rename(f.path);
}

/// Читает файл и проверяет его разбором [parse]; если основной файл повреждён или
/// потерян, пробует временную и резервную копии. Возвращает null, если ничего не подошло.
Future<T?> readValid<T>(File f, Future<T> Function(Uint8List bytes) parse) async {
  for (final p in [f.path, '${f.path}.tmp', '${f.path}.bak']) {
    final c = File(p);
    try {
      if (!await c.exists()) continue;
      return await parse(await c.readAsBytes());
    } catch (_) {
      continue;
    }
  }
  return null;
}

Future<bool> saveBytes(String name, List<int> bytes) async {
  final data = Uint8List.fromList(bytes);
  final path = await FilePicker.platform.saveFile(fileName: name, bytes: data);
  if (path == null) return false;
  if (isDesktop) {
    await File(path).writeAsBytes(data);
  }
  return true;
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

Future<void> copyClear(String text, {int seconds = 30}) async {
  await Clipboard.setData(ClipboardData(text: text));
  Timer(Duration(seconds: seconds), () async {
    final d = await Clipboard.getData('text/plain');
    if (d?.text == text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}

List<List<String>> parseCsv(String input) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final sb = StringBuffer();
  var inQ = false;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQ) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        sb.write(ch);
      }
    } else {
      if (ch == '"') {
        inQ = true;
      } else if (ch == ',') {
        row.add(sb.toString());
        sb.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(sb.toString());
        sb.clear();
        rows.add(row);
        row = <String>[];
      } else {
        sb.write(ch);
      }
    }
    i++;
  }
  if (sb.isNotEmpty || row.isNotEmpty) {
    row.add(sb.toString());
    rows.add(row);
  }
  return rows.where((r) => !(r.length == 1 && r[0].isEmpty)).toList();
}

String csvEscape(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String toCsv(List<List<String>> rows) =>
    rows.map((r) => r.map(csvEscape).join(',')).join('\n');

String unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&amp;', '&');

String escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Выполняет задачи с ограничением числа одновременных (по умолчанию 5).
/// Первая ошибка останавливает запуск новых задач и пробрасывается после завершения текущих.
Future<void> runPool(Iterable<Future<void> Function()> tasks, {int limit = 5}) async {
  final it = tasks.iterator;
  Object? err;
  StackTrace? st;
  Future<void> worker() async {
    while (err == null && it.moveNext()) {
      final t = it.current;
      try {
        await t();
      } catch (e, s) {
        err ??= e;
        st ??= s;
      }
    }
  }

  await Future.wait([for (var i = 0; i < limit; i++) worker()]);
  if (err != null) Error.throwWithStackTrace(err!, st!);
}

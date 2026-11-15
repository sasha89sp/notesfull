import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'backup.dart';
import 'import_model.dart';
import 'md5.dart';
import 'models.dart';

part 'import_parsers_2.dart';


/// Задание для фонового изолята: формат и пути (файлы или одна папка).
class ImpJob {
  final String kind; // enex | html | md | mdfm | obsidian | txt
  final List<String> paths;
  final bool dir;
  ImpJob(this.kind, this.paths, this.dir);
}

List<ImpNote> impParse(ImpJob j) => _Parser(j).run();

/// Папка Joplin RAW → tar (тот же формат, что внутри JEX).
List<int> rawDirToTar(String dir) {
  final ar = Archive();
  final root = Directory(dir);
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(root.path.length).replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
    final b = e.readAsBytesSync();
    ar.addFile(ArchiveFile(rel, b.length, b));
  }
  return TarEncoder().encode(ar);
}

const _mimes = {
  'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif',
  'webp': 'image/webp', 'bmp': 'image/bmp', 'svg': 'image/svg+xml', 'pdf': 'application/pdf',
};

String _ext(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i + 1).toLowerCase();
}

String _base(String p) {
  final n = p.replaceAll('\\', '/').split('/').last;
  final i = n.lastIndexOf('.');
  return i <= 0 ? n : n.substring(0, i);
}

String _read(File f) {
  var t = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
  if (t.startsWith('﻿')) t = t.substring(1);
  return t;
}

String _unxml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&amp;', '&');
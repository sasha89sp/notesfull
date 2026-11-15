part of 'remote.dart';


/// Обычная папка на устройстве (внешний диск, папка, которую синхронизирует другая программа).
class LocalRemote extends Remote {
  final String base;
  LocalRemote(String dir) : base = dir.replaceAll(RegExp(r'[\\/]+$'), '');

  @override
  String get label => base;

  String _p(String path) {
    if (path.contains('..')) throw 'Недопустимый путь';
    final p = path.replaceAll('/', Platform.pathSeparator);
    return '$base${p.startsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$p';
  }

  @override
  Future<void> mkcol(String path) async {
    try {
      await Directory(_p(path)).create(recursive: true);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> get(String path) async {
    final f = File(_p(path));
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> put(String path, List<int> data) async {
    final f = File(_p(path));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    try {
      final f = File(_p(path));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<List<String>> list(String path) async {
    final d = Directory(_p(path));
    if (!await d.exists()) return [];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is File) {
        final n = e.uri.pathSegments.last;
        if (!n.endsWith('.tmp')) out.add(n);
      }
    }
    return out;
  }

  @override
  Future<List<String>> listDirs(String path) async {
    final d = Directory(_p(path));
    if (!await d.exists()) return [];
    final out = <String>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is Directory) {
        final segs = e.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) out.add(segs.last);
      }
    }
    return out;
  }

  @override
  Future<void> putAtomic(String path, List<int> data) async {
    final f = File(_p(path));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(f.path);
  }
}
// ▸ Каталог данных приложения. В портативном режиме Windows (файл `portable.txt`
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Каталог данных приложения. В портативном режиме Windows (файл `portable.txt`
/// рядом с программой) всё хранится в папке `data` рядом с exe — можно носить на флешке.
class AppDirs {
  static Directory? _base;

  static Directory get exeDir => File(Platform.resolvedExecutable).parent;

  static String _sep(Directory d, String n) => '${d.path}${Platform.pathSeparator}$n';

  /// Включён ли портативный режим (только Windows).
  static bool get portable => Platform.isWindows && File(_sep(exeDir, 'portable.txt')).existsSync();

  static Future<Directory> base() async {
    if (_base != null) return _base!;
    Directory d;
    if (portable) {
      d = Directory(_sep(exeDir, 'data'));
    } else {
      d = await getApplicationSupportDirectory();
    }
    if (!await d.exists()) await d.create(recursive: true);
    return _base = d;
  }

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      final name = e.path.split(Platform.pathSeparator).last;
      final dst = _sep(to, name);
      if (e is Directory) {
        await _copy(e, Directory(dst));
      } else if (e is File) {
        await e.copy(dst);
      }
    }
  }

  /// Включить портативный режим: копирует данные в `data` рядом с exe. Действует после перезапуска.
  static Future<String> enablePortable() async {
    if (!Platform.isWindows) return 'Портативный режим доступен только в Windows';
    final src = await getApplicationSupportDirectory();
    final dst = Directory(_sep(exeDir, 'data'));
    try {
      if (await src.exists()) await _copy(src, dst);
      await File(_sep(exeDir, 'portable.txt')).writeAsString('ASRbox portable: данные хранятся в папке data рядом с программой.\n');
    } catch (e) {
      return 'Не удалось (нет прав записи в папку программы?): $e';
    }
    return 'Готово. Перезапустите программу — данные теперь в ${dst.path}';
  }

  /// Выключить: возвращает данные в обычную папку. Действует после перезапуска.
  static Future<String> disablePortable() async {
    if (!Platform.isWindows) return '';
    try {
      final dst = await getApplicationSupportDirectory();
      final src = Directory(_sep(exeDir, 'data'));
      if (await src.exists()) await _copy(src, dst);
      await File(_sep(exeDir, 'portable.txt')).delete();
    } catch (e) {
      return 'Не удалось: $e';
    }
    return 'Готово. Перезапустите программу — данные снова в профиле пользователя.';
  }
}

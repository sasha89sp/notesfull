// ▸ Часть backup.dart: Backup (полный бэкап профиля, страховочные копии safety/), Jex (импорт/экспорт Joplin JEX, экспорт Markdown, b
part of 'backup.dart';


JexParsed _parseIso(List<int> bytes) => JexParse.parse(bytes);

List<int> _zipIso(Map<String, Uint8List> files) {
  final ar = Archive();
  files.forEach((name, bytes) => ar.addFile(ArchiveFile(name, bytes.length, bytes)));
  return ZipEncoder().encode(ar)!;
}
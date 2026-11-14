import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'backup.dart';
import 'models.dart';
import 'store.dart';

/// Экспорт заметок в PDF. Текст — из того же Markdown, что и в экспорте MD
/// (заголовки, списки, таблицы, код); вложения-картинки в PDF не включаются.
class PdfExport {
  static pw.Font? _reg, _bold;

  static Future<void> _fonts() async {
    _reg ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  }

  static List<pw.Widget> _render(Note n) {
    final out = <pw.Widget>[
      pw.Text(n.title.isEmpty ? 'Без названия' : n.title,
          style: pw.TextStyle(font: _bold, fontSize: 20)),
      pw.SizedBox(height: 8),
    ];
    var code = false;
    final mono = pw.TextStyle(font: _reg, fontSize: 9);
    for (final raw in Jex.bodyLines(n)) {
      final line = raw;
      if (line.trimLeft().startsWith('```')) {
        code = !code;
        continue;
      }
      if (code) {
        out.add(pw.Container(
            color: PdfColors.grey200, padding: const pw.EdgeInsets.symmetric(horizontal: 4), child: pw.Text(line, style: mono)));
        continue;
      }
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (h != null) {
        final lvl = h.group(1)!.length;
        out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
            child: pw.Text(h.group(2)!, style: pw.TextStyle(font: _bold, fontSize: 18 - lvl * 1.5))));
      } else if (line.trim().isEmpty) {
        out.add(pw.SizedBox(height: 5));
      } else if (RegExp(r'^\s*\|[\s:\-|]+\|\s*$').hasMatch(line)) {
        continue; // разделитель таблицы
      } else if (line.trimLeft().startsWith('|')) {
        final cells = line.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
        out.add(pw.Row(children: [
          for (final c in cells)
            pw.Expanded(
                child: pw.Container(
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.4)),
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(c, style: pw.TextStyle(font: _reg, fontSize: 10)))),
        ]));
      } else {
        out.add(pw.Text(line.replaceAll(RegExp(r'!?\[([^\]]*)\]\(:/[^)]*\)'), r'[$1]'),
            style: pw.TextStyle(font: _reg, fontSize: 11, lineSpacing: 2)));
      }
    }
    return out;
  }

  /// Одна заметка или несколько (каждая с новой страницы).
  static Future<List<int>> build(Store s, List<Note> notes) async {
    await _fonts();
    final doc = pw.Document(title: notes.length == 1 ? notes.first.title : 'ASRbox');
    for (final n in notes.where((n) => !n.deleted)) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: _reg!, bold: _bold!),
        build: (_) => _render(n),
      ));
    }
    return doc.save();
  }
}

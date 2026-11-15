import 'dart:convert';
import 'package:archive/archive.dart';
import 'formula.dart';
import 'models.dart';
import 'util.dart';

/// Минимальный импорт/экспорт .xlsx (значения, формулы, объединение ячеек).
class Xlsx {
  static List<int> export(TableData t, String sheetName) {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (var r = 0; r < t.rows; r++) {
      sb.write('<row r="${r + 1}">');
      for (var c = 0; c < t.cols; c++) {
        final v = t.cells[r][c].v;
        if (v.isEmpty) continue;
        final ref = '${colName(c)}${r + 1}';
        if (v.startsWith('=')) {
          sb.write('<c r="$ref"><f>${escapeXml(v.substring(1))}</f></c>');
        } else if (double.tryParse(v.replaceAll(',', '.')) != null &&
            !RegExp(r'^0\d').hasMatch(v)) {
          sb.write('<c r="$ref"><v>${v.replaceAll(',', '.')}</v></c>');
        } else {
          sb.write(
              '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${escapeXml(v)}</t></is></c>');
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (t.merges.isNotEmpty) {
      sb.write('<mergeCells count="${t.merges.length}">');
      for (final m in t.merges) {
        sb.write(
            '<mergeCell ref="${colName(m.c)}${m.r + 1}:${colName(m.c + m.cs - 1)}${m.r + m.rs}"/>');
      }
      sb.write('</mergeCells>');
    }
    sb.write('</worksheet>');

    final safe = sheetName.replaceAll(RegExp(r'[\[\]\\/*?:]'), '_');
    final name = safe.isEmpty ? 'Лист1' : (safe.length > 31 ? safe.substring(0, 31) : safe);

    final ar = Archive();
    void add(String path, String data) {
      final b = utf8.encode(data);
      ar.addFile(ArchiveFile(path, b.length, b));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${escapeXml(name)}" sheetId="1" r:id="rId1"/></sheets></workbook>');
    add('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>');
    add('xl/worksheets/sheet1.xml', sb.toString());

    return ZipEncoder().encode(ar)!;
  }

  static TableData import(List<int> bytes) {
    final ar = ZipDecoder().decodeBytes(bytes);
    String? read(String path) {
      for (final f in ar.files) {
        if (f.name == path) return utf8.decode(f.content as List<int>);
      }
      return null;
    }

    final shared = <String>[];
    final ss = read('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(ss)) {
        final sbuf = StringBuffer();
        for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
            .allMatches(si.group(1)!)) {
          sbuf.write(unescapeXml(t.group(1)!));
        }
        shared.add(sbuf.toString());
      }
    }

    String? sheet = read('xl/worksheets/sheet1.xml');
    if (sheet == null) {
      for (final f in ar.files) {
        if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) {
          sheet = utf8.decode(f.content as List<int>);
          break;
        }
      }
    }
    if (sheet == null) throw 'В файле нет листа';

    final values = <String, String>{};
    var maxR = 0, maxC = 0;
    final cellRe = RegExp(r'<c\s([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
    for (final m in cellRe.allMatches(sheet)) {
      final attrs = m.group(1)!;
      final inner = m.group(2) ?? '';
      final ref = RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs);
      if (ref == null) continue;
      final type = RegExp(r'\bt="([^"]*)"').firstMatch(attrs)?.group(1) ?? 'n';
      final c = colIndex(ref.group(1)!);
      final r = int.parse(ref.group(2)!) - 1;
      String val = '';
      final f = RegExp(r'<f[^>]*>(.*?)</f>', dotAll: true).firstMatch(inner);
      final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner);
      if (f != null && f.group(1)!.isNotEmpty) {
        val = '=${unescapeXml(f.group(1)!)}';
      } else if (type == 's' && v != null) {
        final idx = int.tryParse(v.group(1)!) ?? -1;
        val = idx >= 0 && idx < shared.length ? shared[idx] : '';
      } else if (type == 'inlineStr') {
        final t = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner);
        val = t.map((e) => unescapeXml(e.group(1)!)).join();
      } else if (v != null) {
        val = unescapeXml(v.group(1)!);
      }
      if (val.isEmpty) continue;
      values['$r:$c'] = val;
      if (r + 1 > maxR) maxR = r + 1;
      if (c + 1 > maxC) maxC = c + 1;
    }
    if (maxR > 500) maxR = 500;
    if (maxC > 50) maxC = 50;
    final t = TableData.empty(maxR < 3 ? 3 : maxR, maxC < 3 ? 3 : maxC);
    values.forEach((k, v) {
      final p = k.split(':');
      final r = int.parse(p[0]), c = int.parse(p[1]);
      if (r < t.rows && c < t.cols) t.cells[r][c].v = v;
    });
    for (final m in RegExp(r'<mergeCell\s+ref="([A-Z]+)(\d+):([A-Z]+)(\d+)"')
        .allMatches(sheet)) {
      final c1 = colIndex(m.group(1)!), r1 = int.parse(m.group(2)!) - 1;
      final c2 = colIndex(m.group(3)!), r2 = int.parse(m.group(4)!) - 1;
      if (r2 < t.rows && c2 < t.cols) {
        t.merges.add(Merge(r1, c1, r2 - r1 + 1, c2 - c1 + 1));
      }
    }
    return t;
  }
}

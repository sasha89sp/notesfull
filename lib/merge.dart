import 'dart:convert';
import 'models.dart';

class _Conflict implements Exception {}

String _sig(Block b) => jsonEncode(b.toJson());

/// Трёхсторонний выбор: если менялась только одна сторона — берём её,
/// если обе одинаково — это значение, иначе конфликт.
T _pick<T>(T b, T l, T r) {
  if (l == r) return l;
  if (l == b) return r;
  if (r == b) return l;
  throw _Conflict();
}

String _mergeText(String b, String l, String r) {
  if (l == r) return l;
  if (l == b) return r;
  if (r == b) return l;
  final bl = b.split('\n');
  final ll = l.split('\n');
  final rl = r.split('\n');
  if (bl.length != ll.length || bl.length != rl.length) throw _Conflict();
  final out = <String>[];
  for (var i = 0; i < bl.length; i++) {
    out.add(_pick<String>(bl[i], ll[i], rl[i]));
  }
  return out.join('\n');
}

List<CheckItem> _mergeItems(
    List<CheckItem> b, List<CheckItem> l, List<CheckItem> r) {
  if (b.length != l.length || b.length != r.length) throw _Conflict();
  final out = <CheckItem>[];
  for (var i = 0; i < b.length; i++) {
    out.add(CheckItem(
      _pick<String>(b[i].text, l[i].text, r[i].text),
      _pick<bool>(b[i].done, l[i].done, r[i].done),
    ));
  }
  return out;
}

String _mergesSig(TableData t) =>
    jsonEncode(t.merges.map((m) => m.toJson()).toList());

TableData _mergeTable(TableData b, TableData l, TableData r) {
  if (b.rows != l.rows ||
      b.rows != r.rows ||
      b.cols != l.cols ||
      b.cols != r.cols) {
    throw _Conflict();
  }
  final cells = <List<Cell>>[];
  for (var i = 0; i < b.rows; i++) {
    final row = <Cell>[];
    for (var j = 0; j < b.cols; j++) {
      final bc = b.cells[i][j], lc = l.cells[i][j], rc = r.cells[i][j];
      row.add(Cell(
        _pick<String>(bc.v, lc.v, rc.v),
        _pick<int?>(bc.bg, lc.bg, rc.bg),
        _pick<int?>(bc.fg, lc.fg, rc.fg),
      ));
    }
    cells.add(row);
  }
  final pm = _pick<String>(_mergesSig(b), _mergesSig(l), _mergesSig(r));
  final merges = (jsonDecode(pm) as List)
      .map((e) => Merge.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
  return TableData(cells, merges);
}

Block _mergeBlock(Block b, Block l, Block r) {
  if (b.type != l.type || b.type != r.type) throw _Conflict();
  final out = l.copy();
  switch (b.type) {
    case 'text':
    case 'quote':
    case 'code':
      out.content = _mergeText(b.content, l.content, r.content);
      break;
    case 'checklist':
      out.items = _mergeItems(b.items, l.items, r.items);
      break;
    case 'table':
      out.table = _mergeTable(b.table, l.table, r.table);
      break;
    case 'voice':
      out.content = _mergeText(b.content, l.content, r.content);
      final sb = jsonEncode(b.meta);
      final sl = jsonEncode(l.meta);
      final sr = jsonEncode(r.meta);
      if (sl != sr && sl != sb && sr != sb) throw _Conflict();
      if (sl == sb) out.meta = Map<String, dynamic>.from(r.meta);
      break;
    default:
      throw _Conflict();
  }
  return out;
}

/// Сливает локальную и серверную версии заметки относительно общей базы
/// (последнего синхронизированного состояния). Возвращает null, если базы нет
/// или правки пересеклись в одной и той же строке / ячейке / блоке.
Note? mergeNotes(Note local, Note remote) {
  final base = local.base;
  if (base == null) return null;
  try {
    final m = Note.fromJson(
        jsonDecode(jsonEncode(local.toJson())) as Map<String, dynamic>);
    m.title = _pick<String>(local.baseTitle, local.title, remote.title);
    for (final t in remote.tags) {
      if (!m.tags.contains(t)) m.tags.add(t);
    }

    final bm = {for (final b in base) b.id: b};
    final lm = {for (final b in local.blocks) b.id: b};
    final rm = {for (final b in remote.blocks) b.id: b};
    final out = <Block>[];
    final seen = <String>{};

    void handle(String id) {
      if (!seen.add(id)) return;
      final b = bm[id];
      final l = lm[id];
      final r = rm[id];
      if (l == null && r == null) return;
      if (b == null) {
        if (l != null && r != null) {
          if (_sig(l) == _sig(r)) {
            out.add(l);
          } else {
            throw _Conflict();
          }
        } else {
          out.add((l ?? r)!);
        }
        return;
      }
      if (l == null) {
        // удалено у нас: если на сервере правили — правка важнее удаления
        if (r != null && _sig(r) != _sig(b)) out.add(r);
        return;
      }
      if (r == null) {
        if (_sig(l) != _sig(b)) out.add(l);
        return;
      }
      final sl = _sig(l), sr = _sig(r), sb = _sig(b);
      if (sl == sr || sr == sb) {
        out.add(l);
      } else if (sl == sb) {
        out.add(r);
      } else {
        out.add(_mergeBlock(b, l, r));
      }
    }

    for (final b in local.blocks) {
      handle(b.id);
    }
    for (final b in remote.blocks) {
      handle(b.id);
    }
    for (final b in base) {
      handle(b.id);
    }

    m.blocks = out;
    m.updatedAt = nowMs();
    m.syncedAt = 0;
    return m;
  } on _Conflict {
    return null;
  }
}

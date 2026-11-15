import 'dart:convert';
import 'dart:math';
import 'local_tx.dart';

part 'models_2.dart';
part 'models_3.dart';
part 'models_4.dart';
part 'models_5.dart';
part 'models_6.dart';


String newId() {
  final r = Random.secure();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(1 << 30).toRadixString(36)}';
}

/// Сколько дней удалённые заметки лежат в корзине.
const int kTrashDays = 30;

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String two(int x) => x.toString().padLeft(2, '0');

const List<String> kMonths = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];
const List<String> kMonthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
];
const List<String> kWeekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const List<String> kWeekdaysFull = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'
];

/// «Воскресенье, 15 ноября»
String fmtDayLong(DateTime d) => '${kWeekdaysFull[d.weekday - 1]}, ${d.day} ${kMonths[d.month - 1]}';

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${kMonths[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

String fmtDay(DateTime d) => '${d.day} ${kMonths[d.month - 1]} ${d.year}';
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------- Таблицы

class Cell {
  String v;
  int? bg;
  int? fg;
  Cell([this.v = '', this.bg, this.fg]);

  Map<String, dynamic> toJson() => {
        'v': v,
        if (bg != null) 'b': bg,
        if (fg != null) 'f': fg,
      };

  factory Cell.fromJson(Map<String, dynamic> j) =>
      Cell((j['v'] ?? '') as String, j['b'] as int?, j['f'] as int?);
}

class Merge {
  int r, c, rs, cs;
  Merge(this.r, this.c, this.rs, this.cs);

  Map<String, dynamic> toJson() => {'r': r, 'c': c, 'rs': rs, 'cs': cs};

  factory Merge.fromJson(Map<String, dynamic> j) =>
      Merge(j['r'] as int, j['c'] as int, j['rs'] as int, j['cs'] as int);

  bool covers(int rr, int cc) =>
      rr >= r && rr < r + rs && cc >= c && cc < c + cs;
}

class TableData {
  List<List<Cell>> cells;
  List<Merge> merges;
  TableData(this.cells, [List<Merge>? merges]) : merges = merges ?? [];

  factory TableData.empty(int rows, int cols) => TableData(
      List.generate(rows, (_) => List.generate(cols, (_) => Cell())));

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells[0].length;

  Map<String, dynamic> toJson() => {
        'cells': cells.map((r) => r.map((c) => c.toJson()).toList()).toList(),
        'merges': merges.map((m) => m.toJson()).toList(),
      };

  factory TableData.fromJson(Map<String, dynamic> j) => TableData(
        ((j['cells'] ?? []) as List)
            .map((r) => (r as List)
                .map((c) => Cell.fromJson(Map<String, dynamic>.from(c as Map)))
                .toList())
            .toList(),
        ((j['merges'] ?? []) as List)
            .map((m) => Merge.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
      );

  bool get isEmpty => cells.every((r) => r.every((c) => c.v.trim().isEmpty));

  Merge? mergeAt(int r, int c) {
    for (final m in merges) {
      if (m.covers(r, c)) return m;
    }
    return null;
  }

  void insertRow(int at) {
    cells.insert(at, List.generate(cols, (_) => Cell()));
    for (final m in merges) {
      if (m.r >= at) {
        m.r++;
      } else if (at < m.r + m.rs) {
        m.rs++;
      }
    }
  }

  void insertCol(int at) {
    for (final r in cells) {
      r.insert(at, Cell());
    }
    for (final m in merges) {
      if (m.c >= at) {
        m.c++;
      } else if (at < m.c + m.cs) {
        m.cs++;
      }
    }
  }

  void deleteRow(int at) {
    if (rows <= 1) return;
    cells.removeAt(at);
    final dead = <Merge>[];
    for (final m in merges) {
      if (m.r > at) {
        m.r--;
      } else if (m.r + m.rs > at) {
        if (m.rs == 1) {
          dead.add(m);
        } else {
          m.rs--;
        }
      }
    }
    merges.removeWhere(dead.contains);
  }

  void deleteCol(int at) {
    if (cols <= 1) return;
    for (final r in cells) {
      r.removeAt(at);
    }
    final dead = <Merge>[];
    for (final m in merges) {
      if (m.c > at) {
        m.c--;
      } else if (m.c + m.cs > at) {
        if (m.cs == 1) {
          dead.add(m);
        } else {
          m.cs--;
        }
      }
    }
    merges.removeWhere(dead.contains);
  }

  void mergeRange(int r1, int c1, int r2, int c2) {
    final rr1 = min(r1, r2), rr2 = max(r1, r2);
    final cc1 = min(c1, c2), cc2 = max(c1, c2);
    unmergeRange(rr1, cc1, rr2, cc2);
    if (rr1 == rr2 && cc1 == cc2) return;
    for (var r = rr1; r <= rr2; r++) {
      for (var c = cc1; c <= cc2; c++) {
        if (r != rr1 || c != cc1) cells[r][c].v = '';
      }
    }
    merges.add(Merge(rr1, cc1, rr2 - rr1 + 1, cc2 - cc1 + 1));
  }

  void unmergeRange(int r1, int c1, int r2, int c2) {
    merges.removeWhere((m) =>
        m.r <= max(r1, r2) &&
        m.r + m.rs - 1 >= min(r1, r2) &&
        m.c <= max(c1, c2) &&
        m.c + m.cs - 1 >= min(c1, c2));
  }
}

// ---------------------------------------------------------------- Блоки

/// type: text | checklist | quote | code | table | voice | image | file
class CheckItem {
  String text;
  bool done;
  CheckItem(this.text, [this.done = false]);

  Map<String, dynamic> toJson() => {'t': text, 'd': done};

  factory CheckItem.fromJson(Map<String, dynamic> j) =>
      CheckItem((j['t'] ?? '') as String, (j['d'] ?? false) as bool);
}
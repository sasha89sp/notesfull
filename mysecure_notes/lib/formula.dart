import 'models.dart';

String colName(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int colIndex(String s) {
  var n = 0;
  for (final ch in s.toUpperCase().split('')) {
    n = n * 26 + (ch.codeUnitAt(0) - 64);
  }
  return n - 1;
}

String fmtNum(double v) {
  if (v.isNaN || v.isInfinite) return '#ЧИСЛО!';
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsFixed(6);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

class _Err implements Exception {
  final String m;
  _Err(this.m);
}

/// Вычисление формул: + - * / ( ), ячейки A1, диапазоны A1:B3,
/// функции SUM, AVERAGE, MIN, MAX, COUNT.
class Evaluator {
  final TableData t;
  final Map<String, String> _cache = {};
  final Set<String> _stack = {};

  Evaluator(this.t);

  String display(int r, int c) {
    if (r < 0 || c < 0 || r >= t.rows || c >= t.cols) return '';
    final raw = t.cells[r][c].v;
    if (!raw.startsWith('=')) return raw;
    final key = '$r:$c';
    if (_cache.containsKey(key)) return _cache[key]!;
    if (_stack.contains(key)) return '#ЦИКЛ!';
    _stack.add(key);
    String out;
    try {
      final p = _Parser(raw.substring(1), this);
      final v = p.parseAll();
      out = fmtNum(v);
    } on _Err catch (e) {
      out = e.m;
    } catch (_) {
      out = '#ОШИБКА!';
    }
    _stack.remove(key);
    _cache[key] = out;
    return out;
  }

  double? num(int r, int c) {
    if (r < 0 || c < 0 || r >= t.rows || c >= t.cols) return null;
    final d = display(r, c);
    if (d.startsWith('#')) throw _Err(d);
    return double.tryParse(d.replaceAll(',', '.').trim());
  }
}

class _Parser {
  final String s;
  final Evaluator ev;
  int i = 0;
  _Parser(this.s, this.ev);

  double parseAll() {
    final v = _expr();
    _ws();
    if (i < s.length) throw _Err('#ОШИБКА!');
    return v;
  }

  void _ws() {
    while (i < s.length && s[i] == ' ') {
      i++;
    }
  }

  double _expr() {
    var v = _term();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i++];
        final r = _term();
        v = op == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  double _term() {
    var v = _unary();
    while (true) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final op = s[i++];
        final r = _unary();
        if (op == '/') {
          if (r == 0) throw _Err('#ДЕЛ/0!');
          v = v / r;
        } else {
          v = v * r;
        }
      } else {
        return v;
      }
    }
  }

  double _unary() {
    _ws();
    if (i < s.length && s[i] == '-') {
      i++;
      return -_unary();
    }
    if (i < s.length && s[i] == '+') {
      i++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    _ws();
    if (i >= s.length) throw _Err('#ОШИБКА!');
    if (s[i] == '(') {
      i++;
      final v = _expr();
      _ws();
      if (i >= s.length || s[i] != ')') throw _Err('#ОШИБКА!');
      i++;
      return v;
    }
    final num = RegExp(r'\d+([.,]\d+)?').matchAsPrefix(s, i);
    if (num != null) {
      i = num.end;
      return double.parse(num.group(0)!.replaceAll(',', '.'));
    }
    final id = RegExp(r'[A-Za-zА-Яа-я]+\d*').matchAsPrefix(s, i);
    if (id == null) throw _Err('#ОШИБКА!');
    final name = id.group(0)!;
    i = id.end;
    _ws();
    // функция
    if (i < s.length && s[i] == '(') {
      i++;
      final vals = <double>[];
      while (true) {
        _ws();
        if (i < s.length && s[i] == ')') {
          i++;
          break;
        }
        vals.addAll(_arg());
        _ws();
        if (i < s.length && (s[i] == ',' || s[i] == ';')) {
          i++;
        }
      }
      return _func(name.toUpperCase(), vals);
    }
    // ссылка на ячейку
    final m = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(name);
    if (m == null) throw _Err('#ИМЯ?');
    final c = colIndex(m.group(1)!);
    final r = int.parse(m.group(2)!) - 1;
    return ev.num(r, c) ?? 0;
  }

  List<double> _arg() {
    _ws();
    final range = RegExp(r'([A-Za-z]+)(\d+):([A-Za-z]+)(\d+)').matchAsPrefix(s, i);
    if (range != null) {
      i = range.end;
      final c1 = colIndex(range.group(1)!);
      final r1 = int.parse(range.group(2)!) - 1;
      final c2 = colIndex(range.group(3)!);
      final r2 = int.parse(range.group(4)!) - 1;
      final out = <double>[];
      for (var r = r1 < r2 ? r1 : r2; r <= (r1 < r2 ? r2 : r1); r++) {
        for (var c = c1 < c2 ? c1 : c2; c <= (c1 < c2 ? c2 : c1); c++) {
          final v = ev.num(r, c);
          if (v != null) out.add(v);
        }
      }
      return out;
    }
    return [_expr()];
  }

  double _func(String f, List<double> v) {
    switch (f) {
      case 'SUM':
      case 'СУММ':
        return v.fold(0.0, (a, b) => a + b);
      case 'AVERAGE':
      case 'СРЗНАЧ':
        if (v.isEmpty) throw _Err('#ДЕЛ/0!');
        return v.fold(0.0, (a, b) => a + b) / v.length;
      case 'MIN':
      case 'МИН':
        return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
      case 'MAX':
      case 'МАКС':
        return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
      case 'COUNT':
      case 'СЧЁТ':
        return v.length.toDouble();
      default:
        throw _Err('#ИМЯ?');
    }
  }
}

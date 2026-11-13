import 'models.dart';

/// Исключение: пользователь отменил синхронизацию.
class SyncCancelled implements Exception {
  @override
  String toString() => 'Синхронизация отменена';
}

class CancelToken {
  bool cancelled = false;
  void check() {
    if (cancelled) throw SyncCancelled();
  }
}

const Map<String, String> kKindNames = {
  'notes': 'заметки',
  'family': 'семейные заметки',
  'folders': 'папки',
  'events': 'события',
  'comments': 'комментарии',
  'attachments': 'вложения',
  'passwords': 'пароли',
  'chat': 'сообщения',
};

/// Счётчики одной синхронизации.
class SyncStats {
  final Map<String, int> up = {};
  final Map<String, int> down = {};
  final List<String> log = [];
  int conflicts = 0;

  void u(String kind, [int n = 1]) {
    if (n > 0) up[kind] = (up[kind] ?? 0) + n;
  }

  void d(String kind, [int n = 1]) {
    if (n > 0) down[kind] = (down[kind] ?? 0) + n;
  }

  void merge(SyncStats o) {
    o.up.forEach(u);
    o.down.forEach(d);
    log.addAll(o.log);
    conflicts += o.conflicts;
  }

  int get upTotal => up.values.fold(0, (a, b) => a + b);
  int get downTotal => down.values.fold(0, (a, b) => a + b);
}

/// Запись истории синхронизации.
class SyncRecord {
  int at;
  String status; // ok | error | cancelled
  List<String> targets; // WebDAV, Google Календарь
  Map<String, int> up;
  Map<String, int> down;
  int conflicts;
  List<String> log;

  SyncRecord({
    required this.at,
    required this.status,
    List<String>? targets,
    Map<String, int>? up,
    Map<String, int>? down,
    this.conflicts = 0,
    List<String>? log,
  })  : targets = targets ?? [],
        up = up ?? {},
        down = down ?? {},
        log = log ?? [];

  String get statusText => status == 'ok'
      ? 'успех'
      : status == 'cancelled'
          ? 'отменено'
          : 'ошибка';

  DateTime get dt => DateTime.fromMillisecondsSinceEpoch(at);

  String get when => '${fmtDay(dt)} ${fmtTime(dt)}';

  static String _fmt(Map<String, int> m) {
    if (m.isEmpty) return '—';
    return m.entries
        .map((e) => '${kKindNames[e.key] ?? e.key}: ${e.value}')
        .join(', ');
  }

  String get sentText => _fmt(up);
  String get receivedText => _fmt(down);

  Map<String, dynamic> toJson() => {
        'at': at,
        'status': status,
        'targets': targets,
        'up': up,
        'down': down,
        'conflicts': conflicts,
        'log': log,
      };

  factory SyncRecord.fromJson(Map<String, dynamic> j) => SyncRecord(
        at: (j['at'] ?? 0) as int,
        status: (j['status'] ?? 'ok') as String,
        targets: ((j['targets'] ?? []) as List).map((e) => e.toString()).toList(),
        up: ((j['up'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        down: ((j['down'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        conflicts: (j['conflicts'] ?? 0) as int,
        log: ((j['log'] ?? []) as List).map((e) => e.toString()).toList(),
      );

  String toText() {
    final b = StringBuffer()
      ..writeln('$when — $statusText')
      ..writeln('Куда: ${targets.isEmpty ? '—' : targets.join(', ')}')
      ..writeln('Отправлено: $sentText')
      ..writeln('Получено: $receivedText');
    if (conflicts > 0) b.writeln('Конфликтов: $conflicts');
    for (final l in log) {
      b.writeln('  • $l');
    }
    return b.toString();
  }
}

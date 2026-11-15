import 'models.dart';
import 'store.dart';

/// Связи между модулями. Данные всех модулей живут в Store, поэтому связи
/// работают и когда сам модуль отключён в настройках (его экран просто не
/// загружается): событие из заметки попадёт в календарь, напоминание сработает.
class Hub {
  /// Событие календаря, привязанное к заметке: создаётся или обновляется.
  static CalEvent eventFromNote(Store s, Note n, DateTime when,
      {int remind = 15, bool task = false}) {
    CalEvent? e;
    for (final x in s.events) {
      if (x.noteId == n.id && !x.deleted) {
        e = x;
        break;
      }
    }
    final start = when.millisecondsSinceEpoch;
    final end = when.add(const Duration(hours: 1)).millisecondsSinceEpoch;
    final title = n.title.trim().isEmpty ? 'Заметка' : n.title.trim();
    if (e == null) {
      e = CalEvent.create(when, task: task);
      e.noteId = n.id;
      e.title = title;
      e.start = start;
      e.end = end;
      e.remind = remind;
      s.events.add(e);
    } else {
      e.title = title;
      e.start = start;
      e.end = end;
      e.remind = remind;
      e.isTask = task;
      e.updatedAt = nowMs();
    }
    s.eventsChanged();
    return e;
  }

  /// Заметка удалена — связанные события тоже.
  static void noteDeleted(Store s, Note n) {
    var any = false;
    for (final e in s.events) {
      if (e.noteId == n.id && !e.deleted) {
        e.deleted = true;
        e.updatedAt = nowMs();
        any = true;
      }
    }
    if (any) s.eventsChanged();
  }

  /// Название заметки изменилось — подтягиваем в событие.
  static void noteRenamed(Store s, Note n) {
    var any = false;
    final t = n.title.trim().isEmpty ? 'Заметка' : n.title.trim();
    for (final e in s.events) {
      if (e.noteId == n.id && !e.deleted && e.title != t) {
        e.title = t;
        e.updatedAt = nowMs();
        any = true;
      }
    }
    if (any) s.eventsChanged();
  }

  /// Сообщение чата → личная заметка.
  static Note noteFromText(Store s, String text, {String title = ''}) {
    final n = Note.create(s.author, s.profileId, 'personal');
    n.title = title.isNotEmpty ? title : (text.length > 40 ? '${text.substring(0, 40)}…' : text);
    n.blocks.add(Block(type: 'text', content: text));
    s.notes.add(n);
    s.changed();
    return n;
  }

  /// Сообщение чата → событие календаря.
  static CalEvent eventFromText(Store s, String text, DateTime when) {
    final e = CalEvent.create(when);
    e.title = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    e.notes = text;
    s.events.add(e);
    s.eventsChanged();
    return e;
  }
}

// ▸ Часть google.dart: Синхронизация с Google Календарём  [содержит: GoogleSync]
part of 'google.dart';

class GoogleSync {


  /// Двусторонняя синхронизация без дублей. Работает порциями и отдаёт управление
  /// интерфейсу, чтобы приложение не зависало на больших календарях.
  static Future<void> sync(Store s, SyncStats r, CancelToken tok) async {
    final tok0 = await GoogleCal._access(s);
    final h = {
      'Authorization': 'Bearer $tok0',
      'Content-Type': 'application/json',
    };

    // 1. читаем изменения с сервера
    s.setProgress('Google: загрузка списка событий…');
    final min = DateTime.now()
        .subtract(const Duration(days: 60))
        .toUtc()
        .toIso8601String();
    final items = <Map<String, dynamic>>[];
    String? page;
    do {
      tok.check();
      final uri = Uri.https(
          'www.googleapis.com', '/calendar/v3/calendars/primary/events', {
        'timeMin': min,
        'singleEvents': 'true',
        'showDeleted': 'true',
        'maxResults': '250',
        if (page != null) 'pageToken': page,
      });
      final resp = await http.get(uri, headers: h);
      if (resp.statusCode != 200) throw 'список событий: ${resp.statusCode}';
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      for (final it in (j['items'] ?? []) as List) {
        items.add(Map<String, dynamic>.from(it as Map));
      }
      page = j['nextPageToken'] as String?;
      await Future<void>.delayed(Duration.zero);
    } while (page != null);

    // индексы: быстрый поиск вместо перебора (перебор вешал интерфейс)
    final byG = <String, CalEvent>{
      for (final e in s.events)
        if (e.gId.isNotEmpty) e.gId: e,
    };
    final unlinked = <String, CalEvent>{};
    for (final e in s.events) {
      if (e.gId.isEmpty && !e.deleted && !e.isTask && GoogleCal._toGoogle(e)) {
        unlinked[GoogleCal._key(e.title, e.start, e.end)] = e;
      }
    }

    var n = 0;
    for (final it in items) {
      tok.check();
      if (++n % 40 == 0) {
        s.setProgress('Google: обработка ${n}/${items.length}',
            items.isEmpty ? null : n / items.length);
        await Future<void>.delayed(Duration.zero);
      }
      final gid = it['id'] as String;
      var local = byG[gid];
      if (it['status'] == 'cancelled') {
        if (local != null && !local.deleted) {
          local.deleted = true;
          local.gId = '';
          local.updatedAt = nowMs();
          r.d('events');
        }
        continue;
      }
      if (it['start'] == null || it['end'] == null) continue;
      final updated =
          DateTime.parse(it['updated'] as String).millisecondsSinceEpoch;
      final allDay = (it['start'] as Map)['date'] != null;
      final start = GoogleCal._parseG(Map<String, dynamic>.from(it['start'] as Map));
      var end = GoogleCal._parseG(Map<String, dynamic>.from(it['end'] as Map));
      if (allDay) end = end.subtract(const Duration(days: 1));
      int remind = -1;
      final rem = it['reminders'];
      if (rem is Map &&
          rem['overrides'] is List &&
          (rem['overrides'] as List).isNotEmpty) {
        remind = ((rem['overrides'] as List).first['minutes'] as num).toInt();
      }
      final title = (it['summary'] ?? '') as String;

      if (local == null) {
        // такое же событие уже есть локально: связываем, а не дублируем
        final k = GoogleCal._key(title, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
        final twin = unlinked.remove(k);
        if (twin != null) {
          twin.gId = gid;
          twin.gSynced = updated;
          twin.gLocal = twin.updatedAt;
          byG[gid] = twin;
          r.log.add('Совпало с существующим: «$title», дубль не создан');
          continue;
        }
        final ev = CalEvent(
          id: newId(),
          title: title,
          notes: (it['description'] ?? '') as String,
          start: start.millisecondsSinceEpoch,
          end: end.millisecondsSinceEpoch,
          allDay: allDay,
          remind: remind,
          gId: gid,
          gSynced: updated,
          gLocal: nowMs(),
          updatedAt: nowMs(),
        );
        s.events.add(ev);
        byG[gid] = ev;
        r.d('events');
      } else if (updated > local.gSynced && local.updatedAt <= local.gLocal) {
        final nt = (it['description'] ?? '') as String;
        final same = local.title == title &&
            local.notes == nt &&
            local.start == start.millisecondsSinceEpoch &&
            local.end == end.millisecondsSinceEpoch &&
            local.allDay == allDay &&
            local.remind == remind;
        local.gSynced = updated;
        if (same) continue; // данные совпадают: ничего не меняем
        local.title = title;
        local.notes = nt;
        local.start = start.millisecondsSinceEpoch;
        local.end = end.millisecondsSinceEpoch;
        local.allDay = allDay;
        local.remind = remind;
        local.updatedAt = nowMs();
        local.gLocal = local.updatedAt;
        r.d('events');
      }
    }

    // 2. отправляем только новые и изменённые (задачи остаются локально)
    final todo = s.events
        .where((e) =>
            !e.isTask &&
            (GoogleCal._toGoogle(e) || e.gId.isNotEmpty) &&
            ((e.deleted && e.gId.isNotEmpty) ||
                (!e.deleted && (e.gId.isEmpty || e.updatedAt > e.gLocal))))
        .toList();
    var m = 0;
    var errs = 0;
    for (final e in todo) {
      tok.check();
      s.setProgress('Google: отправка ${++m}/${todo.length}',
          todo.isEmpty ? null : m / todo.length);
      if (m % 5 == 0) await Future<void>.delayed(Duration.zero);
      try {
        if (e.deleted) {
          await http.delete(
              Uri.https('www.googleapis.com',
                  '/calendar/v3/calendars/primary/events/${e.gId}'),
              headers: h);
          e.gId = '';
          r.u('events');
        } else if (e.gId.isEmpty) {
          final resp = await http.post(
              Uri.https('www.googleapis.com',
                  '/calendar/v3/calendars/primary/events'),
              headers: h,
              body: jsonEncode(GoogleCal._body(e)));
          if (resp.statusCode == 200) {
            final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
            e.gId = j['id'] as String;
            e.gSynced =
                DateTime.parse(j['updated'] as String).millisecondsSinceEpoch;
            e.gLocal = e.updatedAt;
            r.u('events');
          } else if (errs++ < 5) {
            r.log.add('Не отправлено «${e.title}»: HTTP ${resp.statusCode}');
          }
        } else {
          final resp = await http.put(
              Uri.https('www.googleapis.com',
                  '/calendar/v3/calendars/primary/events/${e.gId}'),
              headers: h,
              body: jsonEncode(GoogleCal._body(e)));
          if (resp.statusCode == 200) {
            final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
            e.gSynced =
                DateTime.parse(j['updated'] as String).millisecondsSinceEpoch;
            e.gLocal = e.updatedAt;
            r.u('events');
          } else if (errs++ < 5) {
            r.log.add('Не обновлено «${e.title}»: HTTP ${resp.statusCode}');
          }
        }
      } catch (err) {
        if (err is SyncCancelled) rethrow;
        if (errs++ < 5) r.log.add('Ошибка отправки «${e.title}»: $err');
      }
    }
    if (errs > 5) r.log.add('…и ещё ${errs - 5} ошибок отправки');
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'app_dirs.dart';
import 'ical_sub.dart';
import 'accounts.dart';
import 'applog.dart';
import 'crypto.dart';
import 'google.dart';
import 'groups.dart';
import 'models.dart';
import 'notify.dart';
import 'remote.dart';
import 'sync.dart';
import 'synchist.dart';
import 'util.dart';

part 'store_2.dart';
part 'store_3.dart';
part 'store_4.dart';
part 'store_5.dart';


class ProfileInfo {
  String id;
  String name;
  String kind; // local | online
  String dir; // пусто = корневая папка (профиль из старой версии)
  String uid; // идентификатор аккаунта ASRbox на хранилище (пусто — старый профиль)
  ProfileInfo(
      {required this.id,
      this.name = '',
      this.kind = 'local',
      this.dir = '',
      this.uid = ''});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'kind': kind, 'dir': dir, 'uid': uid};
  factory ProfileInfo.fromJson(Map<String, dynamic> j) => ProfileInfo(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        kind: (j['kind'] ?? 'local') as String,
        dir: (j['dir'] ?? '') as String,
        uid: (j['uid'] ?? '') as String,
      );
}

class Store extends ChangeNotifier {
  /// Локальный индекс: нижний регистр текста каждой заметки, пересобирается только у изменённых.
  final Map<String, (int, String)> _sidx = {};

  late Directory baseDir;
  late Directory dir; // папка текущего профиля
  List<ProfileInfo> profiles = [];
  String curId = '';
  bool wantPicker = false;
  SecretKey? key; // локальный ключ (случайная соль)
  SecretKey? syncKey; // ключ синхронизации личных данных (одинаков на устройствах)
  List<Note> notes = [];
  List<CalEvent> events = [];
  List<Comment> comments = [];
  List<ChatMsg> chat = []; // грузится лениво, только если модуль «Чаты» включён
  bool chatLoaded = false;
  List<NoteFolder> folders = [];
  Settings settings = Settings();
  bool syncing = false;
  String status = '';
  String progressText = '';
  double? progress;
  List<SyncRecord> history = [];
  CancelToken? _tok;
  VoidCallback? onEventsChanged;

  Future<void> _chain = Future.value();
  Timer? _debounce;
  final FlutterSecureStorage _ss = const FlutterSecureStorage();

  // ------------------------------------------------------------ блокировка модулей

  /// Новое в общих папках, найденное при синхронизации: «название группы» → [сообщения, правки].
  final Map<String, List<int>> notices = {};

  final Map<String, int> _modOk = {};

  /// Выбранный день (мини-календарь, панель «Расписание», календарь) и вид календаря.
  DateTime viewDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  String calView = 'month';

  bool _gcalDirty = false; // события менялись локально — Google нужно обновить
  int _lastRun = 0;

  int _lastProgressNotify = 0;}
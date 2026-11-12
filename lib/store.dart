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
import 'crypto.dart';
import 'google.dart';
import 'models.dart';
import 'sync.dart';
import 'util.dart';

class Store extends ChangeNotifier {
  late Directory dir;
  SecretKey? key; // локальный ключ (случайная соль)
  SecretKey? syncKey; // ключ синхронизации личных данных (одинаков на устройствах)
  List<Note> notes = [];
  List<CalEvent> events = [];
  List<Comment> comments = [];
  Settings settings = Settings();
  bool syncing = false;
  String status = '';
  VoidCallback? onEventsChanged;

  SecretKey? _fk;
  String _fkPass = '';
  Future<void> _chain = Future.value();
  Timer? _debounce;
  final FlutterSecureStorage _ss = const FlutterSecureStorage();

  String get author => settings.author.isEmpty ? 'Я' : settings.author;
  String get profileId => settings.profileId;

  Future<void> init() async {
    dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  File _f(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  Future<bool> hasVault() => _f('vault.json').exists();

  // ------------------------------------------------------------ вход

  Future<void> create(String pw) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final k = await Crypto.deriveKey(pw, salt);
    final sk = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
    final check = await Crypto.encrypt(k, utf8.encode('ok'));
    await writeAtomic(
      _f('vault.json'),
      utf8.encode(jsonEncode({
        'salt': base64Encode(salt),
        'check': base64Encode(check),
      })),
    );
    key = k;
    syncKey = sk;
    notes = [];
    events = [];
    comments = [];
    settings = Settings(profileId: newId());
    await save();
  }

  Future<bool> unlock(String pw) async {
    final m = jsonDecode(await _f('vault.json').readAsString())
        as Map<String, dynamic>;
    final salt = base64Decode(m['salt'] as String);
    final k = await Crypto.deriveKey(pw, salt);
    try {
      final ok = await Crypto.decrypt(k, base64Decode(m['check'] as String));
      if (utf8.decode(ok) != 'ok') return false;
    } catch (_) {
      return false;
    }
    key = k;
    syncKey = await Crypto.deriveFixed(pw, 'mysecure-personal-sync-v1');
    await _load();
    return true;
  }

  Future<void> _load() async {
    final k = key!;
    Future<dynamic> readJson(String n) async {
      final f = _f(n);
      if (!await f.exists()) return null;
      final data = await Crypto.decrypt(k, await f.readAsBytes());
      return jsonDecode(utf8.decode(data));
    }

    final n = await readJson('notes.enc');
    notes = n == null
        ? []
        : (n as List)
            .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    final e = await readJson('events.enc');
    events = e == null
        ? []
        : (e as List)
            .map((x) => CalEvent.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
    final c = await readJson('comments.enc');
    comments = c == null
        ? []
        : (c as List)
            .map((x) => Comment.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
    final s = await readJson('settings.enc');
    settings = s == null
        ? Settings()
        : Settings.fromJson(Map<String, dynamic>.from(s as Map));
    if (settings.profileId.isEmpty) {
      settings.profileId = newId();
      await saveSettings();
    }
  }

  // ------------------------------------------------------------ биометрия

  Future<bool> bioAvailable() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> bioStored() async {
    try {
      return (await _ss.read(key: 'k')) != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enableBiometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Подтвердите включение входа по биометрии',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!ok) return false;
      await _ss.write(key: 'k', value: base64Encode(await key!.extractBytes()));
      await _ss.write(
          key: 'sk', value: base64Encode(await syncKey!.extractBytes()));
      settings.bio = true;
      await saveSettings();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disableBiometric() async {
    try {
      await _ss.delete(key: 'k');
      await _ss.delete(key: 'sk');
    } catch (_) {}
    settings.bio = false;
    await saveSettings();
  }

  Future<bool> unlockBio() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Разблокируйте заметки',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!ok) return false;
      final k = await _ss.read(key: 'k');
      final sk = await _ss.read(key: 'sk');
      if (k == null || sk == null) return false;
      key = SecretKey(base64Decode(k));
      syncKey = SecretKey(base64Decode(sk));
      await _load();
      return true;
    } catch (_) {
      key = null;
      syncKey = null;
      return false;
    }
  }

  // ------------------------------------------------------------ сохранение

  Future<void> _saveJson(String name, Object data) {
    _chain = _chain.then((_) async {
      final k = key;
      if (k == null) return;
      final bytes = utf8.encode(jsonEncode(data));
      await writeAtomic(_f(name), await Crypto.encrypt(k, bytes));
    }).catchError((Object e) {
      debugPrint('save error: $e');
    });
    return _chain;
  }

  Future<void> saveNotes() =>
      _saveJson('notes.enc', notes.map((n) => n.toJson()).toList());
  Future<void> saveEvents() =>
      _saveJson('events.enc', events.map((e) => e.toJson()).toList());
  Future<void> saveComments() =>
      _saveJson('comments.enc', comments.map((c) => c.toJson()).toList());
  Future<void> saveSettings() => _saveJson('settings.enc', settings.toJson());

  Future<void> save() async {
    await saveNotes();
    await saveEvents();
    await saveComments();
    await saveSettings();
  }

  void refresh() => notifyListeners();

  /// После изменения заметок
  void changed() {
    notifyListeners();
    saveNotes();
    schedSync();
  }

  void eventsChanged() {
    notifyListeners();
    saveEvents();
    onEventsChanged?.call();
    schedSync();
  }

  void commentsChanged() {
    notifyListeners();
    saveComments();
    schedSync();
  }

  void schedSync() {
    _debounce?.cancel();
    if (settings.syncConfigured || settings.googleConfigured) {
      _debounce = Timer(const Duration(seconds: 5), () => syncAll());
    }
  }

  // ------------------------------------------------------------ поиск

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool isMine(Note n) =>
      (n.authorId.isNotEmpty && n.authorId == settings.profileId) ||
      (n.authorId.isEmpty && n.author == author);

  Future<SecretKey?> familyKey() async {
    if (settings.famKey.isNotEmpty) {
      return SecretKey(base64Decode(settings.famKey));
    }
    final p = settings.familyPass;
    if (p.isEmpty) return null;
    if (_fk == null || _fkPass != p) {
      _fk = await Crypto.deriveFixed(p, 'mysecure-family-v1');
      _fkPass = p;
    }
    return _fk;
  }

  // ------------------------------------------------------------ вложения

  Directory get _attDir =>
      Directory('${dir.path}${Platform.pathSeparator}attachments');

  File attFile(String id) =>
      File('${_attDir.path}${Platform.pathSeparator}$id.enc');

  bool hasAttachment(String id) => attFile(id).existsSync();

  Future<void> writeAttachment(String id, List<int> plain) async {
    if (!await _attDir.exists()) await _attDir.create(recursive: true);
    await writeAtomic(attFile(id), await Crypto.encrypt(key!, plain));
  }

  Future<String> addAttachment(List<int> plain) async {
    final id = newId();
    await writeAttachment(id, plain);
    return id;
  }

  Future<Uint8List?> readAttachment(String id) async {
    final f = attFile(id);
    if (!await f.exists()) return null;
    try {
      return await Crypto.decrypt(key!, await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ синхронизация

  Future<void> syncAll() async {
    if (syncing || key == null) return;
    if (!settings.syncConfigured && !settings.googleConfigured) return;
    syncing = true;
    status = 'Синхронизация…';
    notifyListeners();
    final parts = <String>[];
    if (settings.syncConfigured) {
      try {
        parts.add('WebDAV ${await SyncService.run(this)}');
      } catch (e) {
        parts.add('WebDAV: ошибка — $e');
      }
    }
    if (settings.googleConfigured) {
      try {
        parts.add('Google ${await GoogleCal.sync(this)}');
      } catch (e) {
        parts.add('Google: ошибка — $e');
      }
    }
    status = parts.join('\n');
    syncing = false;
    await save();
    onEventsChanged?.call();
    notifyListeners();
  }

  Future<void> sync() => syncAll();
}

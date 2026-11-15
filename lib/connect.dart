import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'accounts.dart';
import 'applog.dart';
import 'gdrive.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';
import 'sync.dart';
import 'widgets.dart';

part 'connect_2.dart';
part 'connect_3.dart';


/// Двухуровневая авторизация ASRbox:
/// 1) хранилище (WebDAV или папка на устройстве) → 2) папка на нём →
/// 3) собственный логин и пароль в приложении.
/// На одном WebDAV может жить сколько угодно аккаунтов: данные каждого лежат в
/// своей папке и зашифрованы его паролем.
class ConnectScreen extends StatefulWidget {
  final Store store;
  const ConnectScreen({super.key, required this.store});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  int _step = 0;
  String _kind = 'webdav';
  final _gId = TextEditingController();
  final _gSecret = TextEditingController();
  String _gdToken = '';
  final _url = TextEditingController(text: 'https://webdav.cloud.mail.ru');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _path = TextEditingController();
  final _newFolder = TextEditingController(text: 'ASRbox');
  final _login = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  Remote? _remote;
  List<String> _dirs = [];
  String? _picked; // выбранная существующая папка
  bool _legacy = false;
  bool _legacyAvail = false;
  bool _askRepeat = false;
  bool _remember = true;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    for (final c in [_url, _user, _pass, _path, _newFolder, _login, _pw, _pw2, _gId, _gSecret]) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------- вид

  @override
  Widget build(BuildContext context) {
    final sec = Pal.secondary(context);
    final titles = ['Хранилище', 'Папка', 'Ваш аккаунт'];
    return Scaffold(
      appBar: AppBar(title: Text('Подключение · ${titles[_step]}')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Шаг ${_step + 1} из 3',
                    textAlign: TextAlign.center, style: TextStyle(color: sec, fontSize: 12)),
                const SizedBox(height: 16),
                if (_step == 0) ..._stepStorage(sec),
                if (_step == 1) ..._stepFolder(sec),
                if (_step == 2) ..._stepAccount(sec),
                if (_err != null) ...[
                  const SizedBox(height: 12),
                  Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: Pal.error(context))),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }}
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ctx_menu.dart';
import 'models.dart';
import 'panes.dart';
import 'pass_io.dart';
import 'pass_store.dart';
import 'store.dart';
import 'totp.dart';
import 'util.dart';
import 'widgets.dart';

part 'pass_page_2.dart';
part 'pass_page_3.dart';
part 'pass_page_4.dart';
part 'pass_page_5.dart';


String generatePassword(
    {int length = 20,
    bool upper = true,
    bool lower = true,
    bool digits = true,
    bool symbols = true}) {
  const u = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const l = 'abcdefghijkmnopqrstuvwxyz';
  const d = '23456789';
  const s = '!@#\$%^&*()-_=+[]{};:,.?';
  final pools = <String>[
    if (upper) u,
    if (lower) l,
    if (digits) d,
    if (symbols) s,
  ];
  if (pools.isEmpty) pools.add(l);
  final r = Random.secure();
  final chars = <String>[];
  for (final p in pools) {
    chars.add(p[r.nextInt(p.length)]);
  }
  final all = pools.join();
  while (chars.length < length) {
    chars.add(all[r.nextInt(all.length)]);
  }
  chars.shuffle(r);
  return chars.take(length).join();
}

Future<String?> showGenerator(BuildContext context) {
  var len = 20.0;
  var up = true, lo = true, di = true, sy = true;
  var pw = generatePassword();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        void regen() => set(() => pw = generatePassword(
            length: len.round(), upper: up, lower: lo, digits: di, symbols: sy));
        return AlertDialog(
          title: const Text('Генератор паролей'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SelectableText(pw,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
              Row(children: [
                Text('Длина ${len.round()}'),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 64,
                    value: len,
                    onChanged: (v) {
                      len = v;
                      regen();
                    },
                  ),
                ),
              ]),
              CheckboxListTile(
                  dense: true,
                  title: const Text('A–Z'),
                  value: up,
                  onChanged: (v) {
                    up = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('a–z'),
                  value: lo,
                  onChanged: (v) {
                    lo = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('0–9'),
                  value: di,
                  onChanged: (v) {
                    di = v ?? true;
                    regen();
                  }),
              CheckboxListTile(
                  dense: true,
                  title: const Text('Символы'),
                  value: sy,
                  onChanged: (v) {
                    sy = v ?? true;
                    regen();
                  }),
            ]),
          ),
          actions: [
            TextButton(onPressed: regen, child: const Text('Ещё')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, pw),
                child: const Text('Использовать')),
          ],
        );
      },
    ),
  );
}

// =============================================================== страница

class PassPage extends StatefulWidget {
  final Store store;
  final PassStore pass;
  final bool desktop; // трёхблочный вид для компьютера
  const PassPage({super.key, required this.store, required this.pass, this.desktop = false});
  @override
  State<PassPage> createState() => _PassPageState();
}

class _PassPageState extends State<PassPage> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _search = TextEditingController();
  String? _err;
  bool _busy = false;
  bool _save = false;
  int _saveMin = 30; // -1 — до выхода из профиля
  String _folder = '\u0000all'; // \u0000all | \u0000fav | имя папки
  String _q = '';
  PassEntry? _sel; // выбранная запись (десктоп)
  bool _selNew = false;
  int _selSeq = 0;

  @override
  void initState() {
    super.initState();
    setSecure(true);
    p.tryAutoUnlock();
  }

  @override
  void dispose() {
    setSecure(false);
    _pw.dispose();
    _pw2.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: p,
      builder: (context, _) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => p.touch(),
        child: p.unlocked ? (widget.desktop ? _desktop() : _list()) : _lockForm(),
      ),
    );
  }}
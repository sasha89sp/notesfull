import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';

/// Windows: трей, сворачивание вместо закрытия, всплывающее окно-напоминание.
class Desktop with TrayListener, WindowListener {
  static final Desktop I = Desktop._();
  Desktop._();

  final ValueNotifier<CalEvent?> alert = ValueNotifier<CalEvent?>(null);
  final List<CalEvent> _queue = [];
  bool hidden = false;
  bool popup = false;
  bool _wasHidden = false;
  Rect? _saved;
  AudioPlayer? _player;

  bool get enabled => Platform.isWindows;

  Future<void> init() async {
    if (!enabled) return;
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1000, 720),
      minimumSize: Size(420, 560),
      title: 'Заметки',
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    try {
      await trayManager.setIcon('assets/tray.ico');
      await trayManager.setToolTip('Заметки');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Открыть'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Выход'),
      ]));
    } catch (_) {}
  }

  // ---------------- окно и трей

  @override
  void onWindowClose() {
    _handleClose();
  }

  Future<void> _handleClose() async {
    if (popup) {
      await closeAlert(open: false);
      return;
    }
    await windowManager.hide();
    hidden = true;
  }

  @override
  void onTrayIconMouseDown() {
    showMain();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      showMain();
    } else if (menuItem.key == 'exit') {
      exitApp();
    }
  }

  Future<void> showMain() async {
    if (!enabled) return;
    await windowManager.show();
    await windowManager.focus();
    hidden = false;
  }

  Future<void> exitApp() async {
    await _stopSound();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ---------------- всплывающее напоминание

  Future<void> showAlert(CalEvent e) async {
    if (!enabled) return;
    if (popup) {
      _queue.add(e);
      return;
    }
    popup = true;
    _wasHidden = hidden;
    try {
      _saved = await windowManager.getBounds();
      await windowManager.setMinimumSize(const Size(300, 200));
      final v = ui.PlatformDispatcher.instance.views.first;
      final sz = v.display.size / v.display.devicePixelRatio;
      await windowManager.setSize(const Size(400, 230));
      await windowManager.setPosition(
          Offset(sz.width - 400 - 16, sz.height - 230 - 64));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      hidden = false;
    } catch (_) {}
    alert.value = e;
    await _startSound();
  }

  Future<void> closeAlert({required bool open}) async {
    await _stopSound();
    if (_queue.isNotEmpty && !open) {
      alert.value = _queue.removeAt(0);
      await _startSound();
      return;
    }
    _queue.clear();
    popup = false;
    alert.value = null;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(420, 560));
      final b = _saved;
      if (b != null) {
        await windowManager.setSize(b.size);
        await windowManager.setPosition(b.topLeft);
      }
      if (open) {
        await windowManager.show();
        await windowManager.focus();
        hidden = false;
      } else if (_wasHidden) {
        await windowManager.hide();
        hidden = true;
      }
    } catch (_) {}
  }

  Future<void> _startSound() async {
    try {
      _player ??= AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.play(AssetSource('alert.wav'));
    } catch (_) {}
  }

  Future<void> _stopSound() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

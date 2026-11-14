import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'applog.dart';
import 'autofill.dart';
import 'desktop.dart';
import 'lock.dart';
import 'notify.dart';
import 'pass_store.dart';
import 'shell.dart';
import 'status_strip.dart';
import 'store.dart';
import 'transfer_screen.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AppLog.I.init();
    FlutterError.onError = (d) {
      AppLog.I.e('flutter', d.exceptionAsString(), d.stack);
      FlutterError.presentError(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      AppLog.I.e('platform', '$e', st);
      return true;
    };
    if (Platform.isWindows) {
      await Desktop.I.init();
    }
    final af = await autofillRequest();
    runApp(App(autofill: af));
  }, (e, st) => AppLog.I.e('zone', '$e', st));
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? Colors.black : Colors.white;
  final accent = dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  final fg = dark ? Colors.white : Colors.black;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: b)
        .copyWith(primary: accent),
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: bg),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      indicatorColor: accent.withOpacity(0.18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class App extends StatefulWidget {
  final AutofillRequest? autofill;
  const App({super.key, this.autofill});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final Store store = Store();
  late final PassStore pass = PassStore(store);
  bool _ready = false;
  bool _exists = false;
  bool _unlocked = false;
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await store.init();
    final e = await store.hasVault();
    if (!mounted) return;
    setState(() {
      _exists = e;
      _ready = true;
    });
  }

  /// Выход из профиля / смена профиля: возвращаемся на экран входа.
  Future<void> _logout(bool picker) async {
    navKey.currentState?.popUntil((r) => r.isFirst);
    await pass.forgetSaved();
    pass.lock();
    await store.logout(picker: picker);
    if (!mounted) return;
    setState(() {
      _unlocked = false;
      _exists = store.profiles.isNotEmpty;
    });
  }

  ThemeMode _modeOf(String v) =>
      v == 'dark' ? ThemeMode.dark : v == 'light' ? ThemeMode.light : ThemeMode.system;

  Future<void> _onUnlocked() async {
    _mode = _modeOf(store.settings.theme);
    await pass.init();
    if (widget.autofill == null) await Notifier.I.init(store);
    setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (!_ready) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!_unlocked) {
      home = LockScreen(store: store, exists: _exists, onDone: _onUnlocked);
    } else if (widget.autofill != null) {
      home = AutofillPicker(pass: pass, request: widget.autofill!);
    } else {
      home = Shell(
        store: store,
        pass: pass,
        onLogout: _logout,
        onTheme: (v) {
          store.settings.theme = v;
          store.saveSettings();
          setState(() => _mode = _modeOf(v));
        },
      );
    }
    return MaterialApp(
      title: 'ASRbox',
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final mq = MediaQuery.of(context);
          final desk = _unlocked && store.useDesktop(mq.size.width);
          // в режиме компьютера всё мельче и плотнее; масштаб настраивается
          final sc = _unlocked ? store.settings.fontScale * (desk ? 0.88 : 1.0) : 1.0;
          final strip = _unlocked && widget.autofill == null && StatusStrip.visible(store);
          Widget body = Column(children: [
            Expanded(
                child: strip
                    ? MediaQuery.removeViewPadding(
                        context: context,
                        removeBottom: true,
                        child: child ?? const SizedBox.shrink())
                    : (child ?? const SizedBox.shrink())),
            if (_unlocked && widget.autofill == null)
              StatusStrip(
                  store: store,
                  compact: desk,
                  onOpen: () => navKey.currentState?.push(MaterialPageRoute<void>(
                      builder: (_) => TransferScreen(store: store)))),
          ]);
          if (desk) {
            body = Theme(
                data: Theme.of(context).copyWith(visualDensity: VisualDensity.compact),
                child: body);
            // Ctrl + колесо мыши и Ctrl +/−/0 — масштаб интерфейса
            void zoom(double d) {
              store.settings.fontScale =
                  d == 0 ? 1.0 : (store.settings.fontScale + d).clamp(0.7, 1.6);
              store.saveSettings();
              store.refresh();
            }

            body = CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.equal, control: true): () => zoom(0.1),
                const SingleActivator(LogicalKeyboardKey.add, control: true): () => zoom(0.1),
                const SingleActivator(LogicalKeyboardKey.minus, control: true): () => zoom(-0.1),
                const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => zoom(0),
              },
              child: Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
                    zoom(e.scrollDelta.dy < 0 ? 0.05 : -0.05);
                  }
                },
                child: Focus(autofocus: false, child: body),
              ),
            );
          }
          return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * sc)),
              child: body);
        },
      ),
      home: home,
    );
  }
}

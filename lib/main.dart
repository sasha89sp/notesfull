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
  const lightBg = Color(0xFFFAFAF9);
  const sidebar = Color(0xFFF4F4F5);
  const darkBg = Color(0xFF09090B);
  const indigo = Color(0xFF4F46E5);
  final bg = dark ? darkBg : lightBg;
  final fg = dark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);
  final line = dark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
  final surface = dark ? const Color(0xFF18181B) : Colors.white;
  final accent = dark ? const Color(0xFF818CF8) : indigo;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: accent,
    secondary: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    surface: surface,
    onSurface: fg,
    outline: line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    dividerColor: line,
    canvasColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      iconTheme: IconThemeData(color: dark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B), size: 20),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: dark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
    dividerTheme: DividerThemeData(color: line, thickness: 0.7, space: 1),
    drawerTheme: DrawerThemeData(backgroundColor: dark ? const Color(0xFF111113) : sidebar),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line, width: 0.7),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: dark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B),
      textColor: fg,
      selectedColor: accent,
      selectedTileColor: accent.withOpacity(0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      minLeadingWidth: 24,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: fg, fontSize: 14, height: 1.5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      showDragHandle: true,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: line)),
      textStyle: TextStyle(color: fg, fontSize: 13),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF27272A) : const Color(0xFF27272A),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: accent.withOpacity(.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: line),
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: fg,
        elevation: 0,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
      indicatorColor: accent,
      dividerColor: line,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: accent.withOpacity(.12)),
    textSelectionTheme: TextSelectionThemeData(cursorColor: accent, selectionColor: accent.withOpacity(.22), selectionHandleColor: accent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF18181B) : sidebar,
      indicatorColor: accent.withOpacity(0.14),
      elevation: 0,
      labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(
        color: states.contains(MaterialState.selected) ? accent : (dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A)),
        fontSize: 11,
        fontWeight: states.contains(MaterialState.selected) ? FontWeight.w600 : FontWeight.w400,
      )),
    ),
    textTheme: Typography.material2021().black.apply(bodyColor: fg, displayColor: fg),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      hintStyle: TextStyle(color: dark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA), fontSize: 13),
      labelStyle: TextStyle(color: dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A), fontSize: 13),
      floatingLabelStyle: TextStyle(color: accent, fontSize: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? Colors.white : (dark ? const Color(0xFFA1A1AA) : Colors.white)),
      trackColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? accent : (dark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8))),
    ),
    radioTheme: RadioThemeData(fillColor: MaterialStateProperty.all(accent)),
    sliderTheme: SliderThemeData(activeTrackColor: accent, thumbColor: accent, overlayColor: accent.withOpacity(.12)),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: dark ? const Color(0xFF52525B) : const Color(0xFFD4D4D8), width: 1.4),
      fillColor: MaterialStateProperty.resolveWith((states) =>
          states.contains(MaterialState.selected) ? accent : Colors.transparent),
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

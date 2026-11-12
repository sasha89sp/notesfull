#!/usr/bin/env python3
"""Патчит сгенерированный flutter create проект Android: разрешения, ресиверы,
desugaring (flutter_local_notifications), FlutterFragmentActivity (local_auth),
AppCompat-тема, FLAG_SECURE через MethodChannel."""
import pathlib
import re

root = pathlib.Path('android')

# ---------- AndroidManifest ----------
m = root / 'app/src/main/AndroidManifest.xml'
t = m.read_text(encoding='utf-8')
perms = ['INTERNET', 'POST_NOTIFICATIONS', 'SCHEDULE_EXACT_ALARM', 'USE_EXACT_ALARM',
         'RECEIVE_BOOT_COMPLETED', 'VIBRATE', 'USE_BIOMETRIC', 'RECORD_AUDIO', 'WAKE_LOCK']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in perms)
if 'POST_NOTIFICATIONS' not in t:
    t = t.replace('<application', add + '    <application', 1)

receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
if 'ScheduledNotificationReceiver' not in t:
    t = t.replace('</application>', receivers + '    </application>', 1)
t = re.sub(r'android:label="[^"]*"', 'android:label="Заметки"', t, count=1)
m.write_text(t, encoding='utf-8')

# ---------- Gradle: core library desugaring ----------
for name in ['app/build.gradle.kts', 'app/build.gradle']:
    p = root / name
    if not p.exists():
        continue
    s = p.read_text(encoding='utf-8')
    if 'coreLibraryDesugaring' in s:
        continue
    kts = name.endswith('.kts')
    s = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion',
               'minSdk = 24' if kts else 'minSdkVersion 24', s)
    s = re.sub(r'(release\s*\{)',
               (r'\1\n            isMinifyEnabled = false\n            isShrinkResources = false') if kts
               else (r'\1\n            minifyEnabled false\n            shrinkResources false'),
               s, count=1)
    if kts:
        s = re.sub(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', s, count=1)
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        s = re.sub(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', s, count=1)
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    p.write_text(s, encoding='utf-8')

# ---------- Темы (BiometricPrompt требует AppCompat) ----------
for f in root.rglob('styles.xml'):
    s = f.read_text(encoding='utf-8')
    parent = 'Theme.AppCompat.NoActionBar' if 'night' in str(f.parent) else 'Theme.AppCompat.Light.NoActionBar'
    s = re.sub(r'parent="@android:style/Theme\.[A-Za-z.]*"', f'parent="{parent}"', s)
    f.write_text(s, encoding='utf-8')

# ---------- MainActivity ----------
acts = list(root.rglob('MainActivity.kt'))
if acts:
    a = acts[0]
    pkg = re.search(r'^package\s+(\S+)', a.read_text(encoding='utf-8'), re.M).group(1)
    a.write_text(f'''package {pkg}

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mysecure/native")
            .setMethodCallHandler {{ call, result ->
                if (call.method == "secure") {{
                    val on = call.arguments as? Boolean ?: false
                    runOnUiThread {{
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }}
                    result.success(null)
                }} else {{
                    result.notImplemented()
                }}
            }}
    }}
}}
''', encoding='utf-8')

# --- Все библиотеки (плагины) собираем с compileSdk 36: часть плагинов
# (flutter_plugin_android_lifecycle) требует его, а file_picker указывает 34.
KTS = """
subprojects {
    val fixSdk = Action<Project> {
        val ext = extensions.findByName("android")
        if (ext != null) {
            try {
                ext.javaClass
                    .getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(ext, 36)
            } catch (e: Exception) {
                println("compileSdk patch skipped for " + name + ": " + e)
            }
        }
    }
    if (state.executed) fixSdk.execute(this) else afterEvaluate(fixSdk)
}
"""
GROOVY = """
subprojects {
    def fixSdk = { Project pr ->
        if (pr.extensions.findByName("android") != null) {
            pr.android.compileSdkVersion 36
        }
    }
    if (project.state.executed) { fixSdk(project) } else { project.afterEvaluate(fixSdk) }
}
"""
for name, code in [('build.gradle.kts', KTS), ('build.gradle', GROOVY)]:
    f = root / name
    if f.exists():
        t = f.read_text(encoding='utf-8')
        if 'fixSdk' not in t:
            f.write_text(t + code, encoding='utf-8')
        print('compileSdk patch ->', name)
print('android patched')

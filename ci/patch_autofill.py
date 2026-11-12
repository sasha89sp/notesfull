#!/usr/bin/env python3
"""Добавляет в Android-проект сервис автозаполнения паролей (Kotlin).
Запускается после patch_android.py, только в варианте сборки «autofill»."""
import pathlib
import re

root = pathlib.Path('android')

acts = list(root.rglob('MainActivity.kt'))
assert acts, 'MainActivity.kt not found'
main = acts[0]
pkg = re.search(r'^package\s+(\S+)', main.read_text(encoding='utf-8'), re.M).group(1)
kdir = main.parent

main.write_text(f'''package {pkg}

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterFragmentActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mysecure/native")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "secure" -> {{
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {{
                            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }}
                        result.success(null)
                    }}
                    "autofillSupported" -> result.success(Build.VERSION.SDK_INT >= 26)
                    "autofillRequest" -> {{
                        if (intent != null && intent.hasExtra("af_pkg")) {{
                            result.success(
                                mapOf(
                                    "pkg" to (intent.getStringExtra("af_pkg") ?: ""),
                                    "domain" to (intent.getStringExtra("af_domain") ?: "")
                                )
                            )
                        }} else {{
                            result.success(null)
                        }}
                    }}
                    "autofillResult" -> {{
                        val m = call.arguments as? Map<*, *>
                        deliverAutofill(
                            (m?.get("username") as? String) ?: "",
                            (m?.get("password") as? String) ?: ""
                        )
                        result.success(null)
                    }}
                    "autofillCancel" -> {{
                        setResult(Activity.RESULT_CANCELED)
                        finish()
                        result.success(null)
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}

    private fun deliverAutofill(user: String, pass: String) {{
        if (Build.VERSION.SDK_INT < 26) return
        @Suppress("DEPRECATION")
        val userId = intent.getParcelableExtra<AutofillId>("af_user")
        @Suppress("DEPRECATION")
        val passId = intent.getParcelableExtra<AutofillId>("af_pass")
        val pres = RemoteViews(packageName, android.R.layout.simple_list_item_1)
        pres.setTextViewText(android.R.id.text1, "Заметки")
        @Suppress("DEPRECATION")
        val ds = Dataset.Builder(pres)
        if (userId != null) ds.setValue(userId, AutofillValue.forText(user))
        if (passId != null) ds.setValue(passId, AutofillValue.forText(pass))
        val resp = FillResponse.Builder().addDataset(ds.build()).build()
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, resp)
        )
        finish()
    }}
}}
''', encoding='utf-8')

(kdir / 'AutofillAuthActivity.kt').write_text(f'''package {pkg}

/** Окно, в котором пользователь выбирает пароль для автозаполнения. */
class AutofillAuthActivity : MainActivity()
''', encoding='utf-8')

(kdir / 'MySecureAutofillService.kt').write_text(f'''package {pkg}

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.app.assist.AssistStructure
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews

class MySecureAutofillService : AutofillService() {{

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {{
        val structure = request.fillContexts.last().structure
        val pkg = structure.activityComponent?.packageName ?: ""
        var domain = ""
        var userId: AutofillId? = null
        var passId: AutofillId? = null
        var lastText: AutofillId? = null

        fun walk(node: AssistStructure.ViewNode) {{
            val id = node.autofillId
            if (id != null && node.autofillType == View.AUTOFILL_TYPE_TEXT) {{
                val hints = node.autofillHints?.toList() ?: emptyList()
                val inType = node.inputType
                val isPass = hints.contains(View.AUTOFILL_HINT_PASSWORD) ||
                    (inType and InputType.TYPE_TEXT_VARIATION_PASSWORD) != 0 ||
                    (inType and InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD) != 0
                val isUser = hints.contains(View.AUTOFILL_HINT_USERNAME) ||
                    hints.contains(View.AUTOFILL_HINT_EMAIL_ADDRESS)
                if (isPass && passId == null) {{
                    passId = id
                }} else if (isUser && userId == null) {{
                    userId = id
                }} else if (!isPass && passId == null) {{
                    lastText = id
                }}
                val wd = node.webDomain
                if (domain.isEmpty() && wd != null) domain = wd
            }}
            for (i in 0 until node.childCount) walk(node.getChildAt(i))
        }}

        for (w in 0 until structure.windowNodeCount) {{
            walk(structure.getWindowNodeAt(w).rootViewNode)
        }}

        val p = passId
        val u = userId ?: lastText
        if (p == null && u == null) {{
            callback.onSuccess(null)
            return
        }}
        val ids = ArrayList<AutofillId>()
        if (u != null) ids.add(u)
        if (p != null) ids.add(p)

        val intent = Intent(this, AutofillAuthActivity::class.java)
            .putExtra("af_pkg", pkg)
            .putExtra("af_domain", domain)
            .putExtra("af_user", u)
            .putExtra("af_pass", p)
        val pending = PendingIntent.getActivity(
            this,
            1001,
            intent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        val pres = RemoteViews(packageName, android.R.layout.simple_list_item_1)
        pres.setTextViewText(android.R.id.text1, "Заметки: подобрать пароль")

        val resp = FillResponse.Builder()
            .setAuthentication(ids.toTypedArray(), pending.intentSender, pres)
            .build()
        callback.onSuccess(resp)
    }}

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {{
        callback.onSuccess()
    }}
}}
''', encoding='utf-8')

# --- AndroidManifest
m = root / 'app/src/main/AndroidManifest.xml'
t = m.read_text(encoding='utf-8')
if 'MySecureAutofillService' not in t:
    block = '''
        <activity
            android:name=".AutofillAuthActivity"
            android:exported="false"
            android:theme="@style/NormalTheme"
            android:windowSoftInputMode="adjustResize" />
        <service
            android:name=".MySecureAutofillService"
            android:label="Заметки"
            android:exported="true"
            android:permission="android.permission.BIND_AUTOFILL_SERVICE">
            <intent-filter>
                <action android:name="android.service.autofill.AutofillService" />
            </intent-filter>
            <meta-data
                android:name="android.autofill"
                android:resource="@xml/autofill_service" />
        </service>
'''
    t = t.replace('</application>', block + '    </application>', 1)
    m.write_text(t, encoding='utf-8')

xml = root / 'app/src/main/res/xml'
xml.mkdir(parents=True, exist_ok=True)
(xml / 'autofill_service.xml').write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<autofill-service xmlns:android="http://schemas.android.com/apk/res/android" />\n',
    encoding='utf-8')

# --- Gradle: minSdk 26 (Autofill API), без lint-блокировок
for name in ['app/build.gradle.kts', 'app/build.gradle']:
    p = root / name
    if not p.exists():
        continue
    s = p.read_text(encoding='utf-8')
    kts = name.endswith('.kts')
    s = re.sub(r'minSdk(Version)?\s*=?\s*\d+', 'minSdk = 26' if kts else 'minSdkVersion 26', s, count=1)
    if 'checkReleaseBuilds' not in s:
        lint = ('\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n' if kts
                else '\n    lintOptions {\n        checkReleaseBuilds false\n        abortOnError false\n    }\n')
        s = re.sub(r'(\bandroid\s*\{)', r'\1' + lint.replace('\\', '\\\\'), s, count=1)
    p.write_text(s, encoding='utf-8')
print('autofill patched')

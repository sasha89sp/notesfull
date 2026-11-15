#!/usr/bin/env python3
"""Модуль «Бэкап» (Android): разрешения и нативный мост для звонков, контактов, SMS и Wi-Fi.
Запускается после patch_android.py (и patch_autofill.py, если он используется)."""
import pathlib
import re

root = pathlib.Path('android')

# ---------- разрешения ----------
m = root / 'app/src/main/AndroidManifest.xml'
t = m.read_text(encoding='utf-8')
perms = ['READ_CALL_LOG', 'WRITE_CALL_LOG', 'READ_CONTACTS', 'WRITE_CONTACTS', 'READ_SMS',
         'ACCESS_WIFI_STATE', 'CHANGE_WIFI_STATE', 'ACCESS_FINE_LOCATION']
add = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n'
              for p in perms if f'android.permission.{p}"' not in t)
if add:
    t = t.replace('<application', add + '    <application', 1)
m.write_text(t, encoding='utf-8')

# ---------- MainActivity ----------
acts = list(root.rglob('MainActivity.kt'))
assert acts, 'MainActivity.kt not found'
main = acts[0]
src = main.read_text(encoding='utf-8')
pkg = re.search(r'^package\s+(\S+)', src, re.M).group(1)

if 'BackupBridge.install' not in src:
    src = src.replace('super.configureFlutterEngine(flutterEngine)',
                      'super.configureFlutterEngine(flutterEngine)\n        BackupBridge.install(this, flutterEngine)', 1)
    hook = '''
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        BackupBridge.onPermissions(requestCode, grantResults)
    }
'''
    src = re.sub(r'((?:open\s+)?class MainActivity\s*:\s*FlutterFragmentActivity\(\)\s*\{)',
                 lambda mm: mm.group(1) + hook, src, count=1)
    if 'import io.flutter.embedding.engine.FlutterEngine' not in src:
        raise SystemExit('unexpected MainActivity')
    main.write_text(src, encoding='utf-8')

(main.parent / 'BackupBridge.kt').write_text('''package PKG

import android.Manifest
import android.app.Activity
import android.content.ContentProviderOperation
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** Мост модуля «Бэкап»: чтение и запись журнала звонков, контактов, SMS и сетей Wi-Fi. */
object BackupBridge {
    private var act: Activity? = null
    private var pending: MethodChannel.Result? = null

    fun install(a: Activity, engine: FlutterEngine) {
        act = a
        MethodChannel(engine.dartExecutor.binaryMessenger, "asrbox/backup")
            .setMethodCallHandler { call, result ->
                try {
                    handle(call.method, call.arguments, result)
                } catch (e: Throwable) {
                    result.error("err", e.toString(), null)
                }
            }
    }

    fun onPermissions(code: Int, grants: IntArray) {
        if (code != 7001) return
        val r = pending
        pending = null
        r?.success(grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED })
    }

    private fun perms(g: String): Array<String> = when (g) {
        "calls" -> arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.WRITE_CALL_LOG)
        "contacts" -> arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS)
        "sms" -> arrayOf(Manifest.permission.READ_SMS)
        "wifi" -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        else -> arrayOf()
    }

    private fun has(a: Activity, g: String): Boolean =
        perms(g).all { a.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun bg(a: Activity, result: MethodChannel.Result, f: () -> Any?) {
        Thread {
            try {
                val r = f()
                a.runOnUiThread { result.success(r) }
            } catch (e: Throwable) {
                a.runOnUiThread { result.error("err", e.toString(), null) }
            }
        }.start()
    }

    private fun handle(method: String, args: Any?, result: MethodChannel.Result) {
        val a = act ?: run { result.error("err", "Нет активности", null); return }
        when (method) {
            "hasPerms" -> result.success(has(a, args as String))
            "requestPerms" -> {
                val g = args as String
                if (has(a, g)) { result.success(true); return }
                pending = result
                a.requestPermissions(perms(g), 7001)
            }
            "exportCalls" -> bg(a, result) { exportCalls(a) }
            "importCalls" -> bg(a, result) { importCalls(a, args as String) }
            "exportContacts" -> bg(a, result) { exportContacts(a) }
            "importContacts" -> bg(a, result) { importContacts(a, args as String) }
            "exportSms" -> bg(a, result) { exportSms(a) }
            "importSms" -> bg(a, result) { importSms(a, args as String) }
            "isDefaultSms" -> result.success(Telephony.Sms.getDefaultSmsPackage(a) == a.packageName)
            "exportWifi" -> bg(a, result) { exportWifi(a) }
            "importWifi" -> bg(a, result) { importWifi(a, args as String) }
            else -> result.notImplemented()
        }
    }

    private fun s(c: android.database.Cursor, i: Int): String = c.getString(i) ?: ""

    private fun exportCalls(a: Activity): String {
        val arr = JSONArray()
        val cols = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE,
            CallLog.Calls.DURATION, CallLog.Calls.CACHED_NAME)
        a.contentResolver.query(CallLog.Calls.CONTENT_URI, cols, null, null, CallLog.Calls.DATE + " DESC")?.use { c ->
            while (c.moveToNext()) {
                val o = JSONObject()
                o.put("number", s(c, 0)); o.put("type", c.getInt(1)); o.put("date", c.getLong(2))
                o.put("duration", c.getLong(3)); o.put("name", s(c, 4))
                arr.put(o)
            }
        }
        return arr.toString()
    }

    private fun importCalls(a: Activity, json: String): Int {
        val have = HashSet<String>()
        a.contentResolver.query(CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.DATE), null, null, null)?.use { c ->
            while (c.moveToNext()) have.add(s(c, 0) + "|" + c.getLong(1))
        }
        val arr = JSONArray(json)
        var n = 0
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val num = o.optString("number"); val date = o.optLong("date")
            if (!have.add(num + "|" + date)) continue
            val v = ContentValues()
            v.put(CallLog.Calls.NUMBER, num)
            v.put(CallLog.Calls.TYPE, o.optInt("type", 1))
            v.put(CallLog.Calls.DATE, date)
            v.put(CallLog.Calls.DURATION, o.optLong("duration"))
            v.put(CallLog.Calls.CACHED_NAME, o.optString("name"))
            v.put(CallLog.Calls.NEW, 0)
            if (a.contentResolver.insert(CallLog.Calls.CONTENT_URI, v) != null) n++
        }
        return n
    }

    private fun exportContacts(a: Activity): String {
        val names = LinkedHashMap<Long, String>()
        val phones = HashMap<Long, MutableList<String>>()
        val mails = HashMap<Long, MutableList<String>>()
        val orgs = HashMap<Long, String>()
        val notes = HashMap<Long, String>()
        val cols = arrayOf(ContactsContract.Data.CONTACT_ID, ContactsContract.Data.DISPLAY_NAME,
            ContactsContract.Data.MIMETYPE, ContactsContract.Data.DATA1)
        a.contentResolver.query(ContactsContract.Data.CONTENT_URI, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                names.putIfAbsent(id, s(c, 1))
                val v = s(c, 3)
                if (v.isEmpty()) continue
                when (s(c, 2)) {
                    ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE -> phones.getOrPut(id) { ArrayList() }.add(v)
                    ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE -> mails.getOrPut(id) { ArrayList() }.add(v)
                    ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE -> orgs[id] = v
                    ContactsContract.CommonDataKinds.Note.CONTENT_ITEM_TYPE -> notes[id] = v
                }
            }
        }
        val arr = JSONArray()
        for ((id, name) in names) {
            val o = JSONObject()
            o.put("name", name)
            o.put("phones", JSONArray(phones[id] ?: emptyList<String>()))
            o.put("emails", JSONArray(mails[id] ?: emptyList<String>()))
            o.put("org", orgs[id] ?: "")
            o.put("note", notes[id] ?: "")
            arr.put(o)
        }
        return arr.toString()
    }

    private fun digits(x: String) = x.filter { it.isDigit() }.takeLast(10)

    private fun importContacts(a: Activity, json: String): Int {
        val have = HashSet<String>()
        val cols = arrayOf(ContactsContract.Data.DISPLAY_NAME, ContactsContract.Data.MIMETYPE, ContactsContract.Data.DATA1)
        a.contentResolver.query(ContactsContract.Data.CONTENT_URI, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (s(c, 1) == ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    have.add(s(c, 0).lowercase() + "|" + digits(s(c, 2)))
                else have.add(s(c, 0).lowercase() + "|")
            }
        }
        val arr = JSONArray(json)
        val ops = ArrayList<ContentProviderOperation>()
        var n = 0
        fun flush() {
            if (ops.isNotEmpty()) { a.contentResolver.applyBatch(ContactsContract.AUTHORITY, ops); ops.clear() }
        }
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val name = o.optString("name")
            val ph = o.optJSONArray("phones") ?: JSONArray()
            val em = o.optJSONArray("emails") ?: JSONArray()
            var dup = false
            if (ph.length() == 0) dup = have.contains(name.lowercase() + "|")
            for (j in 0 until ph.length()) if (have.contains(name.lowercase() + "|" + digits(ph.getString(j)))) dup = true
            if (dup) continue
            for (j in 0 until ph.length()) have.add(name.lowercase() + "|" + digits(ph.getString(j)))
            if (ph.length() == 0) have.add(name.lowercase() + "|")
            val idx = ops.size
            ops.add(ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null).build())
            fun data(mime: String): ContentProviderOperation.Builder =
                ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, idx)
                    .withValue(ContactsContract.Data.MIMETYPE, mime)
            ops.add(data(ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name).build())
            for (j in 0 until ph.length())
                ops.add(data(ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, ph.getString(j))
                    .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE).build())
            for (j in 0 until em.length())
                ops.add(data(ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, em.getString(j)).build())
            val org = o.optString("org")
            if (org.isNotEmpty())
                ops.add(data(ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Organization.COMPANY, org).build())
            val note = o.optString("note")
            if (note.isNotEmpty())
                ops.add(data(ContactsContract.CommonDataKinds.Note.CONTENT_ITEM_TYPE)
                    .withValue(ContactsContract.CommonDataKinds.Note.NOTE, note).build())
            n++
            if (ops.size > 300) flush()
        }
        flush()
        return n
    }

    private fun exportSms(a: Activity): String {
        val arr = JSONArray()
        val cols = arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE,
            Telephony.Sms.TYPE, Telephony.Sms.READ)
        a.contentResolver.query(Telephony.Sms.CONTENT_URI, cols, null, null, Telephony.Sms.DATE + " DESC")?.use { c ->
            while (c.moveToNext()) {
                val o = JSONObject()
                o.put("address", s(c, 0)); o.put("body", s(c, 1)); o.put("date", c.getLong(2))
                o.put("type", c.getInt(3)); o.put("read", c.getInt(4))
                arr.put(o)
            }
        }
        return arr.toString()
    }

    /** Возвращает число добавленных SMS, либо -1, если приложение не является SMS-приложением по умолчанию. */
    private fun importSms(a: Activity, json: String): Int {
        if (Telephony.Sms.getDefaultSmsPackage(a) != a.packageName) return -1
        val have = HashSet<String>()
        a.contentResolver.query(Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.DATE), null, null, null)?.use { c ->
            while (c.moveToNext()) have.add(s(c, 0) + "|" + c.getLong(1))
        }
        val arr = JSONArray(json)
        var n = 0
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val addr = o.optString("address"); val date = o.optLong("date")
            if (!have.add(addr + "|" + date)) continue
            val v = ContentValues()
            v.put(Telephony.Sms.ADDRESS, addr)
            v.put(Telephony.Sms.BODY, o.optString("body"))
            v.put(Telephony.Sms.DATE, date)
            v.put(Telephony.Sms.TYPE, o.optInt("type", 1))
            v.put(Telephony.Sms.READ, o.optInt("read", 1))
            if (a.contentResolver.insert(Telephony.Sms.CONTENT_URI, v) != null) n++
        }
        return n
    }

    @Suppress("DEPRECATION")
    private fun exportWifi(a: Activity): String {
        val wm = a.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val arr = JSONArray()
        val seen = HashSet<String>()
        try {
            wm.configuredNetworks?.forEach { n ->
                val ssid = (n.SSID ?: "").trim('"')
                if (ssid.isEmpty() || !seen.add(ssid)) return@forEach
                val o = JSONObject()
                o.put("ssid", ssid)
                o.put("password", (n.preSharedKey ?: "").trim('"'))
                o.put("security", if (n.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.NONE)) "open" else "wpa")
                arr.put(o)
            }
        } catch (_: Throwable) {}
        try {
            val ssid = (wm.connectionInfo?.ssid ?: "").trim('"')
            if (ssid.isNotEmpty() && ssid != "<unknown ssid>" && seen.add(ssid)) {
                val o = JSONObject()
                o.put("ssid", ssid); o.put("password", ""); o.put("security", "wpa")
                arr.put(o)
            }
        } catch (_: Throwable) {}
        return arr.toString()
    }

    @Suppress("DEPRECATION")
    private fun importWifi(a: Activity, json: String): Int {
        val wm = a.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val arr = JSONArray(json)
        if (Build.VERSION.SDK_INT >= 29) {
            val list = ArrayList<WifiNetworkSuggestion>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val ssid = o.optString("ssid")
                if (ssid.isEmpty()) continue
                val b = WifiNetworkSuggestion.Builder().setSsid(ssid)
                val pw = o.optString("password")
                if (pw.length >= 8) b.setWpa2Passphrase(pw)
                list.add(b.build())
            }
            if (list.isEmpty()) return 0
            val st = wm.addNetworkSuggestions(list)
            if (st != WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) throw RuntimeException("Wi-Fi: код $st")
            return list.size
        }
        var n = 0
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val ssid = o.optString("ssid")
            if (ssid.isEmpty()) continue
            val c = WifiConfiguration()
            c.SSID = "\\"" + ssid + "\\""
            val pw = o.optString("password")
            if (pw.isEmpty()) c.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            else c.preSharedKey = "\\"" + pw + "\\""
            if (wm.addNetwork(c) >= 0) n++
        }
        return n
    }
}
'''.replace('package PKG', f'package {pkg}'), encoding='utf-8')
print('backup bridge added')

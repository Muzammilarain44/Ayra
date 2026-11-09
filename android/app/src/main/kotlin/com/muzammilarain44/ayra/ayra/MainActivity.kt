package com.muzammilarain44.ayra.ayra

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Opens installed apps by spoken name, using Android's own PackageManager.
/// No plugin, no API, no account — the phone already knows its apps.
class MainActivity : FlutterActivity() {
    private val channel = "ayra/apps"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "openAppByName") {
                    val query = (call.argument<String>("query") ?: "").lowercase()
                    result.success(openAppByName(query))
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun openAppByName(query: String): Boolean {
        if (query.length < 3 || query == "app") return false
        val pm = packageManager
        val packages = mapOf(
            "chrome" to listOf("com.android.chrome"),
            "whatsapp" to listOf("com.whatsapp"),
            "facebook" to listOf("com.facebook.katana"),
            "instagram" to listOf("com.instagram.android"),
            "spotify" to listOf("com.spotify.music"),
            "gmail" to listOf("com.google.android.gm"),
            "maps" to listOf("com.google.android.apps.maps"),
            "youtube" to listOf("com.google.android.youtube"),
            "telegram" to listOf("org.telegram.messenger"),
            "tiktok" to listOf("com.zhiliaoapp.musically"),
            "play store" to listOf("com.android.vending"),
            "playstore" to listOf("com.android.vending"),
            "files" to listOf("com.google.android.apps.nbu.files"),
            "calculator" to listOf(
                "com.google.android.calculator",
                "com.sec.android.app.popupcalculator",
            ),
            "clock" to listOf(
                "com.google.android.deskclock",
                "com.android.deskclock",
                "com.sec.android.app.clock",
            ),
            "gallery" to listOf(
                "com.google.android.apps.photos",
                "com.sec.android.gallery3d",
            ),
            "photos" to listOf("com.google.android.apps.photos"),
            "settings" to listOf("com.android.settings"),
        )
        for ((key, pkgs) in packages) {
            if (query.contains(key) || (query.length >= 4 && key.contains(query))) {
                for (pkg in pkgs) {
                    val intent = pm.getLaunchIntentForPackage(pkg)
                    if (intent != null) {
                        startActivity(intent)
                        return true
                    }
                }
            }
        }
        // Any other installed app, matched by its display name.
        val mainIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val apps = pm.queryIntentActivities(mainIntent, 0)
        for (info in apps) {
            val label = info.loadLabel(pm).toString().lowercase()
            if (label.contains(query)) {
                val intent = pm.getLaunchIntentForPackage(info.activityInfo.packageName)
                if (intent != null) {
                    startActivity(intent)
                    return true
                }
            }
        }
        return false
    }
}

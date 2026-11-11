package com.muzammilarain44.ayra.ayra

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/// Floating mic button that floats over other apps while the Ayra
/// Assistant is ON. Lives in a process-level object (not the activity)
/// so it survives the activity being minimised or recreated.
/// Tapping it brings Ayra to the front; the Dart side notices the tap
/// and restarts background listening. No always-on mic here — the
/// button is only a shortcut to speak a command.
object AyraOverlay {
    private var view: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var manager: WindowManager? = null

    /// Set when the user taps the button; the Dart side consumes it once.
    @Volatile
    var pendingTap: Boolean = false

    fun isShown(): Boolean = view != null

    fun show(context: Context): Boolean {
        val appContext = context.applicationContext
        if (!Settings.canDrawOverlays(appContext)) return false
        if (view != null) return true
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = appContext.resources.displayMetrics.density

        val button = ImageView(appContext).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            setColorFilter(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#3B82F6"))
                setStroke((2 * density).toInt(), Color.WHITE)
            }
            val pad = (12 * density).toInt()
            setPadding(pad, pad, pad, pad)
            contentDescription = "Ayra — tap to speak"
        }

        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = (300 * density).toInt()
        }

        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        button.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params?.x ?: 0
                    startY = params?.y ?: 0
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (abs(dx) > 10 || abs(dy) > 10) moved = true
                    params?.let { lp ->
                        lp.x = startX + dx
                        lp.y = startY + dy
                        manager?.updateViewLayout(button, lp)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) onTapped(appContext)
                    true
                }
                else -> false
            }
        }

        return try {
            wm.addView(button, p)
            view = button
            params = p
            manager = wm
            true
        } catch (_: Exception) {
            false
        }
    }

    fun hide() {
        val v = view ?: return
        try {
            manager?.removeView(v)
        } catch (_: Exception) {
            // Already gone.
        }
        view = null
        params = null
        manager = null
    }

    private fun onTapped(context: Context) {
        pendingTap = true
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        context.startActivity(intent)
    }
}

/// Opens installed apps by spoken name, using Android's own PackageManager.
/// No plugin, no API, no account — the phone already knows its apps.
/// Also hosts the "ayra/overlay" channel for the floating mic button.
class MainActivity : FlutterActivity() {
    private val channel = "ayra/apps"
    private val overlayChannel = "ayra/overlay"

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, overlayChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showOverlay" -> result.success(AyraOverlay.show(this))
                    "hideOverlay" -> {
                        AyraOverlay.hide()
                        result.success(true)
                    }
                    "isOverlayGranted" ->
                        result.success(Settings.canDrawOverlays(this))
                    "isOverlayRestricted" ->
                        result.success(isOverlayRestricted(this))
                    "requestOverlayPermission" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    "openAppInfoSettings" -> {
                        // App info page: its 3-dot menu holds
                        // "Allow restricted settings".
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    "consumeOverlayTap" -> {
                        val tapped = AyraOverlay.pendingTap
                        AyraOverlay.pendingTap = false
                        result.success(tapped)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// True when Android's "restricted settings" block the overlay
    /// permission. Sideloaded apps (APK file, not Play Store) on
    /// Android 13+ have the SYSTEM_ALERT_WINDOW app-op set to
    /// MODE_ERRORED until the user allows restricted settings
    /// (App info → 3-dot menu → "Allow restricted settings"). A plain
    /// "not granted yet" is MODE_IGNORED / MODE_DEFAULT instead, so
    /// this tells the two cases apart. Only meaningful when the
    /// overlay is not granted. The toggle in "Display over other
    /// apps" is disabled while restricted — the user cannot switch
    /// it on from that screen at all.
    private fun isOverlayRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return false
        }
        if (Settings.canDrawOverlays(context)) return false
        return try {
            val appOps =
                context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                Process.myUid(),
                context.packageName,
            )
            mode == AppOpsManager.MODE_ERRORED
        } catch (_: Exception) {
            false
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

package com.muzammilarain44.ayra.ayra

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

/// Application class — runs before any activity, service or receiver in
/// the app process, which is exactly what the background assistant
/// needs.
///
/// WHY THIS EXISTS: `flutter_foreground_task` creates the background
/// engine as a bare `FlutterEngine(context)` and never registers any
/// plugin on it. The Dart-only registrant
/// (`DartPluginRegistrant.ensureInitialized()`) only registers
/// Dart-only plugins (shared_preferences, url_launcher) — every native
/// plugin (speech_to_text, flutter_tts, permission_handler, ...) is
/// missing there, so the background isolate's very first plugin call
/// threw MissingPluginException and the "Hello Ayra" loop never
/// started, silently. Registering the listener here makes
/// `onEngineCreate` run BEFORE the Dart callback (`startAyraTask`)
/// executes, so `GeneratedPluginRegistrant.registerWith(engine)`
/// gives the background engine the same native plugins as the main
/// engine. Registered in Application.onCreate (not MainActivity) so
/// it also works when the service is started by the system after a
/// phone reboot, when no activity ever runs.
class AyraApplication : Application() {
    companion object {
        @Volatile
        private var listenerAdded = false
    }

    override fun onCreate() {
        super.onCreate()
        if (listenerAdded) return
        listenerAdded = true
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    // Give the background engine every native plugin
                    // the app has, so speech recognition, TTS,
                    // permissions and storage all work there.
                    if (flutterEngine != null) {
                        GeneratedPluginRegistrant.registerWith(flutterEngine)
                    }
                }

                override fun onTaskStart(
                    starter: FlutterForegroundTaskStarter,
                ) {
                    // Nothing native to do here.
                }

                override fun onTaskRepeatEvent() {
                    // Nothing native to do here.
                }

                override fun onTaskDestroy() {
                    // Nothing native to do here.
                }

                override fun onEngineWillDestroy() {
                    // Nothing native to dispose here.
                }
            },
        )
    }
}

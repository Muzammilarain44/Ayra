import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../command_engine.dart';
import '../memory_store.dart';
import 'device_service.dart';
import 'diagnostics_log.dart';
import 'voice_service.dart';

/// Why a background-service start failed, so the UI can show the
/// right message instead of one generic snackbar.
enum AssistantStartFailure {
  /// RECORD_AUDIO is not granted — the mic permission must be allowed
  /// in the UI isolate before ON (Android 14+ refuses a microphone
  /// foreground service without it).
  microphoneDenied,

  /// The service was started while the app was in the background
  /// (Android 12+ ForegroundServiceStartNotAllowedException).
  backgroundStart,

  /// The service did not report running within the plugin's 5-second
  /// deadline.
  timeout,

  /// The service was already running.
  alreadyRunning,

  /// Anything else.
  unknown,
}

/// The result of trying to start the background service.
class AssistantStartResult {
  const AssistantStartResult.ok() : failure = null;
  const AssistantStartResult.failed(this.failure);

  final AssistantStartFailure? failure;

  bool get isOk => failure == null;
}

/// Classifies a plugin start failure into a typed reason. Pure and
/// unit-tested. Matches on the error text because the plugin wraps
/// native exceptions (SecurityException,
/// ForegroundServiceStartNotAllowedException) as PlatformExceptions.
AssistantStartFailure classifyStartError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('timed out')) {
    return AssistantStartFailure.timeout;
  }
  if (text.contains('already started')) {
    return AssistantStartFailure.alreadyRunning;
  }
  if (text.contains('foregroundservicestartnotallowed') ||
      text.contains('not allowed to start') ||
      text.contains('backgroundservice')) {
    return AssistantStartFailure.backgroundStart;
  }
  if (text.contains('securityexception') ||
      text.contains('record_audio') ||
      text.contains('microphone') ||
      text.contains('permission denial')) {
    return AssistantStartFailure.microphoneDenied;
  }
  return AssistantStartFailure.unknown;
}

/// Pure ON/OFF state for the Ayra background assistant. No plugins, so it
/// is unit-testable. The real persistence lives in
/// [BackgroundAssistantService].
class AssistantMode {
  AssistantMode({this.isOn = false});

  /// Restores the mode from a saved value (`null` = never saved = OFF).
  factory AssistantMode.fromSaved(bool? saved) =>
      AssistantMode(isOn: saved ?? false);

  bool isOn;

  /// OFF means Ayra does absolutely nothing — no listening, no service.
  void turnOff() => isOn = false;

  /// ON means the foreground service runs and background listening starts.
  void turnOn() => isOn = true;
}

/// The callback the foreground service runs in its background isolate.
/// Top-level (required) and marked as an entry point so tree-shaking
/// keeps it.
///
/// Plugin registration: `DartPluginRegistrant.ensureInitialized()`
/// covers Dart-only plugins, but the NATIVE plugins (speech_to_text,
/// flutter_tts, permission_handler, ...) are registered by
/// `AyraApplication` — it installs a
/// `FlutterForegroundTaskLifecycleListener` whose `onEngineCreate`
/// calls `GeneratedPluginRegistrant.registerWith(engine)` before this
/// callback ever runs. Without that, the first plugin call in
/// `onStart` threw MissingPluginException and the loop never started.
@pragma('vm:entry-point')
void startAyraTask() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(AyraTaskHandler());
}

/// Owns the trigger loop in the background isolate, so listening keeps
/// working after the user swipes Ayra away from recents (the UI isolate
/// dies then — a loop there is dead the moment the app is swiped away).
///
/// Command routing: the UI isolate sends a heartbeat every 5 seconds
/// while it is alive. When a command is heard and the UI is alive, the
/// command is sent to the UI isolate, which runs it (it has the full
/// app-open channel) and acks; if no ack arrives in 3 seconds, or the
/// UI is dead, the background isolate executes the command itself with
/// the plugins registered here (intents with `FLAG_ACTIVITY_NEW_TASK`,
/// url_launcher, TTS). Display updates are forwarded to the UI when it
/// is open.
///
/// Honest limit: even in the background isolate, Google's recogniser is
/// unreliable with the screen off (Doze suspends Google's service), so
/// screen-off "Hello Ayra" is not guaranteed on every phone.
///
/// Public (not private) so tests can drive `onStart` and prove a
/// failure is surfaced instead of dying silently. Production builds
/// it with no arguments; tests inject fakes and collect the
/// diagnostics it reports.
class AyraTaskHandler extends TaskHandler {
  AyraTaskHandler({
    VoiceService? voice,
    DeviceService? device,
    MemoryStore? store,
    void Function(Map<String, Object> data)? diagnosticSink,
  })  : _voice = voice ?? VoiceService(),
        _device = device ?? DeviceService(),
        _store = store ?? MemoryStore(),
        _diagnosticSink = diagnosticSink ??
            ((data) => FlutterForegroundTask.sendDataToMain(data));

  final VoiceService _voice;
  final DeviceService _device;
  final MemoryStore _store;

  /// Where loop diagnostics go: the UI isolate in production (so the
  /// app can show the loop state), a test collector in tests.
  final void Function(Map<String, Object> data) _diagnosticSink;

  late final CommandEngine _engine;

  DateTime? _lastMainHeartbeat;
  int _nextCommandId = 0;
  final Map<int, Completer<bool>> _pendingAcks = {};
  Timer? _initRetryTimer;
  bool _loopStarted = false;
  bool _loopListening = false;
  String _loopLocale = 'ur-PK';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Every step is guarded. onStart used to die on its very first
    // line (MissingPluginException — no native plugin was registered
    // in this isolate) and the loop never started, silently and
    // permanently. A failure now is reported (debug log +
    // notification + UI) and the retry timer is still armed, instead
    // of the handler dying.
    try {
      final saved = await _store.load();
      _engine = CommandEngine(memories: saved.memories, notes: saved.notes);
    } catch (e) {
      // Saved notes/memories are nice to have, not required to
      // listen — start with an empty engine and keep going.
      _engine = CommandEngine();
      await _reportLoopFailure('Could not load saved data: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _loopLocale =
          prefs.getString(BackgroundAssistantService.loopLocaleKey) ??
              'ur-PK';
    } catch (e) {
      _loopLocale = 'ur-PK';
      await _reportLoopFailure('Could not read settings: $e');
    }
    await _tryStartLoop();
    if (!_loopStarted && !_voice.micPermanentlyDenied) {
      _armRetryTimer();
    }
  }

  /// Retries the loop start every 30s while the service runs, instead
  /// of giving up. (Not when the mic is permanently denied: retrying
  /// can never fix that — _tryStartLoop surfaces it instead.)
  void _armRetryTimer() {
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_loopStarted) {
        _initRetryTimer?.cancel();
        return;
      }
      await _tryStartLoop();
      if (_loopStarted) _initRetryTimer?.cancel();
    });
  }

  /// Records a loop state change in the debug log, the notification
  /// and (when open) the app — so a failure is visible from the
  /// device instead of silent. Never throws.
  Future<void> _reportLoopState(
    String notificationText, {
    required String state,
    String detail = '',
  }) async {
    try {
      await DiagnosticsLog.append('[$state] $notificationText');
    } catch (_) {}
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Ayra chal rahi hai',
        notificationText: notificationText,
      );
    } catch (_) {}
    try {
      _diagnosticSink({
        'type': 'diagnostic',
        'state': state,
        'detail': detail,
        'text': notificationText,
      });
    } catch (_) {}
  }

  /// A loop failure, reported the same way as any other state change.
  Future<void> _reportLoopFailure(String reason) async {
    _loopListening = false;
    await _reportLoopState(
      'Loop failed: $reason — retrying',
      state: 'failed',
      detail: reason,
    );
  }

  /// Loop state changes from the voice service: transitions only for
  /// the notification (a session restarts every few seconds in a
  /// quiet room — the user does not need a buzz each time).
  Future<void> _onLoopEvent(LoopEvent event) async {
    switch (event.kind) {
      case LoopEventKind.listening:
        if (_loopListening) return;
        _loopListening = true;
        await _reportLoopState(
          'Listening… "Hello Ayra" bolo.',
          state: 'listening',
        );
      case LoopEventKind.failed:
        _loopListening = false;
        await _reportLoopFailure(event.detail);
      case LoopEventKind.heard:
        await _reportLoopState(
          'Last heard: "${event.detail}"',
          state: 'heard',
          detail: event.detail,
        );
      case LoopEventKind.fallback:
        await _reportLoopState(
          'On-device sun nahi saka — cloud use ho raha hai',
          state: 'fallback',
          detail: event.detail,
        );
    }
  }

  Future<void> _tryStartLoop() async {
    if (_loopStarted) return;
    bool ok;
    try {
      ok = await _voice.startTriggerLoop(
        localeId: _loopLocale,
        onTriggerCommand: (command) {
          _executeCommand(command);
        },
        onTriggerOnly: () async {
          await _triggerOnlyReply();
        },
        onPartialTranscript: (text) {
          _diagnosticSink({
            'type': 'partial',
            'text': text,
          });
        },
        onLoopEvent: (event) {
          unawaited(_onLoopEvent(event));
        },
      );
    } catch (e) {
      ok = false;
      await _reportLoopFailure('Loop start failed: $e');
    }
    _loopStarted = ok;
    if (!ok) {
      if (_voice.micPermanentlyDenied) {
        // The mic is permanently denied — no retry loop can fix that,
        // so stop retrying and surface it: update the notification
        // (visible even when the app is closed) and tell the UI (when
        // it is open) to send the user to Settings.
        _initRetryTimer?.cancel();
        try {
          await DiagnosticsLog.append(
            '[failed] Microphone permission permanently denied',
          );
        } catch (_) {}
        try {
          await FlutterForegroundTask.updateService(
            notificationTitle: 'Ayra chal rahi hai',
            notificationText:
                'Microphone permission blocked — Settings se Allow karo.',
          );
        } catch (_) {
          // Notification update is best-effort only.
        }
        _diagnosticSink({'type': 'micDenied'});
      } else {
        await _reportLoopFailure('Loop could not start — retrying');
      }
    }
  }

  /// The "Hello Ayra" (trigger-only) reply, in the loop's language —
  /// Urdu is the default, so the reply is Urdu when listening in
  /// Urdu and English otherwise.
  Future<void> _triggerOnlyReply() async {
    final urdu = _loopLocale == 'ur-PK';
    final spoken = urdu ? 'جی، سن رہی ہوں' : "Yes, I'm listening.";
    final display = urdu
        ? 'جی، سن رہی ہوں — کیا کروں؟'
        : "Yes, I'm listening. What should I do?";
    await _voice.speak(spoken, urdu ? 'ur' : 'en');
    _diagnosticSink({
      'type': 'display',
      'heard': 'Hello Ayra',
      'reply': display,
    });
  }

  Future<void> _restartLoopWithLocale() async {
    if (!_loopStarted) return;
    await _voice.stopTriggerLoop();
    _loopStarted = false;
    await _tryStartLoop();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _initRetryTimer?.cancel();
    await _voice.stopTriggerLoop();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    switch (data['type']) {
      case 'heartbeat':
        _lastMainHeartbeat = DateTime.now();
      case 'ack':
        final id = data['id'];
        if (id is int) _pendingAcks[id]?.complete(true);
      case 'locale':
        final locale = data['localeId'];
        if (locale is String && locale != _loopLocale) {
          _loopLocale = locale;
          _restartLoopWithLocale();
        }
      case 'restartLoop':
        _voice.restartTriggerLoop();
      case 'ttsRate':
        // Speaking speed changed in the UI (Slow 0.55 / Normal 0.7)
        // — the background isolate has its own TTS engine, so it
        // needs the new rate too.
        final rate = data['rate'];
        if (rate is num) {
          unawaited(_voice.setSpeechRate(rate.toDouble()));
        }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    // Tapping the notification opens the app (handled by the plugin).
    FlutterForegroundTask.launchApp();
  }

  /// Runs a heard command: prefer the UI isolate (it has the full
  /// app-open channel), fall back to executing here when the UI is
  /// dead or does not ack in time.
  Future<void> _executeCommand(String command) async {
    final id = ++_nextCommandId;
    final mainAlive = _lastMainHeartbeat != null &&
        DateTime.now().difference(_lastMainHeartbeat!) <
            const Duration(seconds: 10);
    if (mainAlive) {
      final ack = Completer<bool>();
      _pendingAcks[id] = ack;
      _diagnosticSink(
        {'type': 'command', 'id': id, 'text': command},
      );
      final gotAck = await ack.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      _pendingAcks.remove(id);
      if (gotAck) return; // Main isolate runs it (and speaks + shows it).
    }
    await _executeLocally(command);
  }

  /// Executes a command in the background isolate, for when the UI
  /// isolate is dead. Same rules as the UI path, minus anything that
  /// needs the screen (confirmations, closing Ayra itself).
  Future<void> _executeLocally(String command) async {
    final result = _engine.handle(command);
    var reply = result.reply;

    switch (result.action) {
      case CommandAction.openSite:
      case CommandAction.searchWeb:
      case CommandAction.dial:
      case CommandAction.sms:
        final ok = await _device.openUrl(result.data ?? '');
        if (!ok) reply = '$reply (Could not open it on this device.)';
        break;
      case CommandAction.battery:
        final level = await _device.batteryLevel();
        reply = level < 0
            ? 'Battery level is not available on this device.'
            : 'Battery is at $level%.';
        break;
      case CommandAction.torchOn:
        final ok = await _device.torchOn();
        if (!ok) reply = 'Torch is not available on this device.';
        break;
      case CommandAction.torchOff:
        final ok = await _device.torchOff();
        if (!ok) reply = 'Torch is not available on this device.';
        break;
      case CommandAction.openApp:
        // The 'ayra/apps' channel lives in MainActivity (main isolate
        // only) — here the well-known package map is used instead.
        final ok = await _device.openAppFromBackground(result.data ?? '');
        if (!ok) {
          // App not installed — open its website instead, when the
          // engine knows one ("WhatsApp kholo" → web.whatsapp.com).
          if (result.fallbackUrl != null) {
            final opened = await _device.openUrl(result.fallbackUrl!);
            reply = opened
                ? 'That app is not installed — opening the website instead.'
                : 'Could not find or open that app on this device.';
          } else {
            reply = 'Could not find or open that app on this device.';
          }
        }
        break;
      case CommandAction.openCamera:
        final ok = await _device.openCamera();
        if (!ok) reply = 'Camera could not be opened on this device.';
        break;
      case CommandAction.setAlarm:
        final parts = (result.data ?? '').split('|');
        final hour = int.tryParse(parts.isEmpty ? '' : parts[0]) ?? 0;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
        final label = parts.length > 2 ? parts[2] : '';
        final ok = await _device.setAlarm(hour, minute, label);
        if (!ok) reply = 'Could not set the alarm on this device.';
        break;
      case CommandAction.openSettings:
        final ok = await _device.openSettings(result.data ?? 'settings');
        if (!ok) reply = 'Could not open settings on this device.';
        break;
      case CommandAction.volumeUp:
        final ok = await _device.volumeUp();
        if (!ok) reply = 'Volume control is not available on this device.';
        break;
      case CommandAction.volumeDown:
        final ok = await _device.volumeDown();
        if (!ok) reply = 'Volume control is not available on this device.';
        break;
      case CommandAction.volumeMute:
        final ok = await _device.volumeMute();
        if (!ok) reply = 'Volume control is not available on this device.';
        break;
      case CommandAction.volumeUnmute:
        final ok = await _device.volumeUnmute();
        if (!ok) reply = 'Volume control is not available on this device.';
        break;
      case CommandAction.closeApp:
        reply =
            'I can only close myself from the app — open Ayra and say it there.';
        break;
      case CommandAction.windowsOrganize:
      case CommandAction.windowsRecycleBin:
      case CommandAction.windowsShutdown:
      case CommandAction.windowsLock:
        reply = 'This only works in the Windows app.';
        break;
      case CommandAction.timerSet:
        _startBackgroundTimer(result);
        break;
      case CommandAction.noteAdd:
      case CommandAction.noteClear:
      case CommandAction.remember:
      case CommandAction.forget:
        await _store.save(_engine.notes, _engine.memories);
        break;
      default:
        break;
    }

    await _voice.speak(reply, result.language);
    _diagnosticSink({
      'type': 'display',
      'heard': command,
      'reply': reply,
    });
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Ayra chal rahi hai',
        notificationText: 'Last: "$command"',
      );
    } catch (_) {
      // Notification update is best-effort only.
    }
  }

  void _startBackgroundTimer(CommandResult result) {
    final parts = (result.data ?? '').split('|');
    final seconds = int.tryParse(parts.first) ?? 0;
    final label = parts.length > 1 ? parts[1] : 'Timer';
    Timer(Duration(seconds: seconds), () async {
      final message = 'Timer done${label == 'Timer' ? '' : ': $label'}.';
      await _voice.speak(message, 'en');
      _diagnosticSink({
        'type': 'display',
        'heard': '⏰ $label',
        'reply': message,
      });
    });
  }
}

/// Wraps the `flutter_foreground_task` plugin (free, MIT) plus the
/// hand-written floating-mic overlay channel in MainActivity.
///
/// Design (as the user asked):
/// - ON: foreground service runs with a persistent notification and the
///   floating mic button appears over other apps. The background isolate
///   listens for "Hello Ayra" (see AyraTaskHandler) — it keeps working
///   after the app is swiped away from recents, which the UI isolate
///   cannot do.
/// - OFF: service stopped, overlay hidden, nothing runs at all.
/// - The ON/OFF choice is saved in SharedPreferences so the toggle
///   shows the right state and the service can be restored after the
///   app is reopened. The plugin itself restarts the service after a
///   phone reboot only when it was ON (its RebootReceiver ignores the
///   boot when the service was stopped properly).
class BackgroundAssistantService {
  static const _prefsKey = 'ayra_assistant_on';

  /// The listen locale the background isolate restores on start
  /// (ur-PK for Urdu — the default — en-US for English/Roman Urdu).
  static const loopLocaleKey = 'ayra_loop_locale';

  static const _overlayChannel = MethodChannel('ayra/overlay');

  static const _notificationChannelId = 'ayra_assistant';
  static const _notificationChannelName = 'Ayra Assistant';
  static const _notificationTitle = 'Ayra chal rahi hai';
  static const _notificationText =
      'ON hai — "Hello Ayra" bolo, ya mic button dabao.';

  bool _initialised = false;

  /// One-time plugin setup. Safe to call repeatedly.
  void init() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _notificationChannelId,
        channelName: _notificationChannelName,
        channelDescription:
            'Ayra background mein chal rahi hai. Band karne ke liye app mein OFF dabao.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The background isolate does the listening (see
        // AyraTaskHandler) — no periodic event needed.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        // Keep running when the user swipes the app away from recents;
        // only the OFF button stops it.
        stopWithTask: false,
      ),
    );
    _initialised = true;
  }

  /// The saved ON/OFF choice.
  Future<bool> isOn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> _save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  /// The listen locale for the background isolate to use.
  Future<String> loopLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(loopLocaleKey) ?? 'ur-PK';
  }

  Future<void> saveLoopLocale(String localeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(loopLocaleKey, localeId);
  }

  /// Sends a message to the background isolate (heartbeat, locale
  /// change, restart). Fire-and-forget.
  static void sendToTask(Map<String, Object> data) {
    FlutterForegroundTask.sendDataToTask(data);
  }

  Future<bool> get isServiceRunning =>
      FlutterForegroundTask.isRunningService;

  /// Starts the foreground service (Android only). Returns a typed
  /// result — the old bool-only version swallowed the reason, so a
  /// fresh install just showed "Could not start the background
  /// service" with no clue why. Never throws.
  Future<AssistantStartResult> start() async {
    if (!Platform.isAndroid) {
      return const AssistantStartResult.failed(
        AssistantStartFailure.unknown,
      );
    }
    init();
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await _save(true);
        return const AssistantStartResult.ok();
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        // microphone only: background listening needs the mic type on
        // Android 14+. (dataSync was dropped — on Android 15 it triggers
        // the 6-hour foreground-service timeout.)
        serviceTypes: const [ForegroundServiceTypes.microphone],
        notificationTitle: _notificationTitle,
        notificationText: _notificationText,
        callback: startAyraTask,
      );
      if (result is ServiceRequestFailure) {
        // Keep the raw error in the log — it is the only trace of
        // what Android actually refused.
        debugPrint('Ayra: startService failed: ${result.error}');
        return AssistantStartResult.failed(
          classifyStartError(result.error),
        );
      }
      await _save(true);
      return const AssistantStartResult.ok();
    } catch (e) {
      debugPrint('Ayra: startService threw: $e');
      return AssistantStartResult.failed(classifyStartError(e));
    }
  }

  /// Stops the service completely and hides the overlay. Never throws.
  Future<void> stop() async {
    try {
      await _overlayHide();
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    await _save(false);
  }

  // ----- Floating mic button (overlay) -----

  /// True when the user allowed "Draw over other apps".
  Future<bool> get canDrawOverlays async {
    if (!Platform.isAndroid) return false;
    try {
      return await _overlayChannel.invokeMethod<bool>('isOverlayGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// True when Android's "restricted settings" block the overlay
  /// permission (sideloaded APK on Android 13+): the toggle in
  /// "Display over other apps" is then disabled and cannot be
  /// switched on until the user allows restricted settings in App
  /// info. Detected natively (see MainActivity) — a plain "not
  /// granted yet" is not restricted.
  Future<bool> get isOverlayRestricted async {
    if (!Platform.isAndroid) return false;
    try {
      return await _overlayChannel.invokeMethod<bool>(
            'isOverlayRestricted',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the app's App info page in system Settings — its 3-dot
  /// menu holds "Allow restricted settings".
  Future<void> openAppInfoSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _overlayChannel.invokeMethod<bool>('openAppInfoSettings');
    } catch (_) {}
  }

  /// Shows the floating mic button over other apps. Returns false when
  /// the overlay permission is missing.
  Future<bool> showOverlay() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _overlayChannel.invokeMethod<bool>('showOverlay') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _overlayHide() async {
    if (!Platform.isAndroid) return;
    try {
      await _overlayChannel.invokeMethod<bool>('hideOverlay');
    } catch (_) {}
  }

  /// Opens the system "Draw over other apps" settings page for Ayra.
  Future<void> openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _overlayChannel.invokeMethod<bool>('requestOverlayPermission');
    } catch (_) {}
  }

  /// True once when the user tapped the floating mic button. The native
  /// side remembers the tap until it is consumed here.
  Future<bool> consumeOverlayTap() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _overlayChannel.invokeMethod<bool>('consumeOverlayTap') ??
          false;
    } catch (_) {
      return false;
    }
  }
}

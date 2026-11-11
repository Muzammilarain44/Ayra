import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'trigger_parser.dart';

/// A state change in the background trigger loop, for diagnostics
/// (notification text, debug log, in-app view).
enum LoopEventKind {
  /// A listen session actually started — the loop is up.
  listening,

  /// A real recogniser failure (not silence).
  failed,

  /// A final transcript arrived (heard words, trigger or not).
  heard,

  /// On-device recognition failed to start repeatedly — the loop
  /// fell back to cloud recognition.
  fallback,
}

/// One loop state change, with a short human-readable detail.
class LoopEvent {
  const LoopEvent(this.kind, [this.detail = '']);

  final LoopEventKind kind;
  final String detail;
}

/// Pure tracker for the error_client trap: when the on-device
/// recogniser cannot start a session at all, Android reports
/// ERROR_CLIENT on every session and the loop would restart every
/// 600 ms forever, never falling back to cloud. Several errors in a
/// row with NO successful session ever means the engine itself is
/// failing to start — then the loop must fall back to cloud.
///
/// A single error after a successful session (for example
/// error_client when a session is stopped) is normal silence and
/// never triggers a fallback.
class LoopErrorTracker {
  /// Errors in a row with no successful session that trigger a
  /// fallback to cloud recognition.
  static const fallbackAfterErrors = 3;

  int _consecutiveErrors = 0;
  bool _hadSuccessfulSession = false;

  /// Call when a recogniser session actually starts ('listening')
  /// or a final transcript arrives.
  void noteSuccess() {
    _consecutiveErrors = 0;
    _hadSuccessfulSession = true;
  }

  /// Call for every recogniser error. Returns true when the loop
  /// should fall back to cloud recognition (several errors, zero
  /// successful sessions ever).
  bool noteError() {
    _consecutiveErrors++;
    if (_consecutiveErrors >= fallbackAfterErrors &&
        !_hadSuccessfulSession) {
      _consecutiveErrors = 0;
      return true;
    }
    return false;
  }

  /// Call when the loop (re)starts — a fresh run has no successes yet.
  void reset() {
    _consecutiveErrors = 0;
    _hadSuccessfulSession = false;
  }

  bool get hadSuccessfulSession => _hadSuccessfulSession;
}

/// How a speech-recognition error should be treated by the trigger loop.
///
/// A quiet room is NOT a failure: the recogniser reports
/// `error_no_match` / `error_speech_timeout` whenever nobody is talking,
/// and `error_client` when a session is stopped. Those just mean "listen
/// again". Only real problems (no network, no mic, no engine, language
/// missing, recogniser busy) count as failures — and even those never
/// stop the loop by themselves; only the user's OFF stops it.
enum LoopErrorKind { silence, realFailure }

/// Errors that only mean "nobody spoke" — restart fast, do not count.
const Set<String> _silenceErrorMessages = {
  'error_no_match',
  'error_speech_timeout',
  'error_client',
};

/// Pure classifier (unit-tested): silence vs. a real failure.
LoopErrorKind classifyLoopError(String errorMsg) =>
    _silenceErrorMessages.contains(errorMsg)
        ? LoopErrorKind.silence
        : LoopErrorKind.realFailure;

/// On-device speech recognition and speech synthesis.
/// Both are free and need no API key. Speech recognition uses the
/// device's own engine (Google on Android, Microsoft on Windows);
/// TTS uses the device's installed voices.
///
/// Two listening modes:
/// - One-shot (the orb): listen once, return the final sentence.
/// - Trigger loop (assistant ON): keep listening in the background and
///   call [onTriggerCommand] only when a sentence contains "Hello Ayra".
///   Transcripts without the trigger are ignored. The loop restarts
///   itself after every final result, error or timeout — and it never
///   stops on its own: silence is normal, real failures back off and
///   retry. Only the user's OFF stops it.
///
/// Honest limit: even in the background isolate, Google's recogniser is
/// unreliable with the screen off (Doze suspends Google's service), so
/// screen-off "Hello Ayra" is not guaranteed on every phone.
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;

  // ----- Background trigger loop -----
  bool _loopActive = false;
  Timer? _loopRestartTimer;
  Timer? _watchdogTimer;
  int _loopFailures = 0;
  String _loopLocale = 'en-US';
  DateTime? _awaitingCommandUntil;
  void Function(String command)? _onTriggerCommand;
  void Function()? _onTriggerOnly;
  void Function(String text)? _onPartialTranscript;

  /// True while the background trigger loop is running.
  bool get isLoopActive => _loopActive;

  /// Last time any recogniser activity arrived (status, result, error
  /// or session start). The watchdog uses it to spot a wedged loop.
  DateTime _lastActivity = DateTime.now();

  /// True once the current locale has no on-device model: later
  /// sessions fall back to cloud recognition instead of failing.
  bool _onDeviceUnavailable = false;

  /// Consecutive recogniser errors with no successful session — see
  /// [LoopErrorTracker]. When it says fall back, the loop switches
  /// to cloud recognition instead of restarting forever on a broken
  /// on-device engine.
  final LoopErrorTracker _errorTracker = LoopErrorTracker();

  /// Reports loop state changes (listening / failed / heard /
  /// fallback) so the background isolate can show them in the
  /// notification, the debug log and the app. Null = nobody listens.
  void Function(LoopEvent event)? _onLoopEvent;

  /// Default speaking speed (Slow). The user asked for it slower
  /// than the old 0.7 — 0.55 is calm and clearly understandable.
  static const double defaultSpeechRate = 0.55;

  /// The "Normal" speed in the UI setting.
  static const double normalSpeechRate = 0.7;

  /// SharedPreferences key for the saved speaking speed.
  static const String ttsRateKey = 'ayra_tts_rate';

  double _speechRate = defaultSpeechRate;

  /// Current speaking speed.
  double get speechRate => _speechRate;

  /// Changes the speaking speed now and saves it, so the background
  /// isolate (which has its own VoiceService) picks it up on its
  /// next initialize() too. Never throws.
  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(0.3, 1.0);
    _speechRate = clamped;
    try {
      await _tts.setSpeechRate(clamped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(ttsRateKey, clamped);
    } catch (_) {}
  }

  /// Reads the saved speaking speed (Slow 0.55 by default).
  Future<double> _loadSpeechRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(ttsRateKey);
      if (saved != null && saved >= 0.3 && saved <= 1.0) return saved;
    } catch (_) {}
    return defaultSpeechRate;
  }

  /// True once the microphone permission is permanently denied — the
  /// background isolate can never fix that by retrying; the user must
  /// allow it in Settings.
  bool _micPermanentlyDenied = false;

  /// True once the microphone permission is permanently denied.
  bool get micPermanentlyDenied => _micPermanentlyDenied;

  /// Initialises speech recognition and the TTS engine.
  /// Returns true when listening is available. Never throws — on a
  /// device without speech support it simply returns false.
  ///
  /// [requestPermission] is true from the UI isolate (the orb — a
  /// permission dialog can be shown there). The background isolate
  /// MUST pass false: no dialog can appear there, so a missing mic
  /// can only be reported, never granted — and the ON flow must have
  /// asked for it in the UI before starting the service.
  Future<bool> initialize({bool requestPermission = true}) async {
    try {
      final status = requestPermission
          ? await Permission.microphone.request()
          : await Permission.microphone.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        _micPermanentlyDenied = status.isPermanentlyDenied;
        return false;
      }
      _micPermanentlyDenied = false;
      _ready = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          if (!_loopActive) return;
          _lastActivity = DateTime.now();
          // Every error counts toward the fallback tracker — several
          // in a row with no successful session means the on-device
          // engine cannot start at all, so fall back to cloud
          // instead of restarting forever on a broken engine.
          if (_errorTracker.noteError() && !_onDeviceUnavailable) {
            _onDeviceUnavailable = true;
            _onLoopEvent?.call(
              const LoopEvent(
                LoopEventKind.fallback,
                'on-device recogniser failed to start — cloud use ho raha hai',
              ),
            );
          }
          if (classifyLoopError(error.errorMsg) == LoopErrorKind.silence) {
            // Quiet room — listen again right away, do not count it.
            _scheduleLoopRestart(delay: const Duration(milliseconds: 600));
            return;
          }
          _onLoopEvent?.call(
            LoopEvent(LoopEventKind.failed, error.errorMsg),
          );
          _noteLoopFailure(error.errorMsg);
        },
        onStatus: (status) {
          if (!_loopActive) return;
          _lastActivity = DateTime.now();
          if (status == 'listening') {
            // A session actually started — the loop is healthy again.
            _loopFailures = 0;
            _errorTracker.noteSuccess();
            _onLoopEvent?.call(const LoopEvent(LoopEventKind.listening));
            return;
          }
          // A finished session reports 'done' / 'doneNoResult' /
          // 'notListening'. In loop mode that just means: listen again.
          if (status == 'done' ||
              status == 'doneNoResult' ||
              status == 'notListening') {
            _loopFailures = 0;
            _scheduleLoopRestart();
          }
        },
      );
      // Speaking speed: Slow 0.55 by default (the user asked for it
      // slower than the old 0.7) — saved choice wins when set.
      _speechRate = await _loadSpeechRate();
      await _tts.setSpeechRate(_speechRate);
      await _tts.setVolume(1.0);
      return _ready;
    } catch (_) {
      return false;
    }
  }

  bool get isListening => _speech.isListening;

  /// Starts listening. Calls [onResult] with the recognised words as
  /// they arrive, and [onFinal] once with the final sentence.
  /// Only for the one-shot orb mode — when the trigger loop is active
  /// the loop already owns the recogniser.
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String text) onFinal,
    String localeId = 'en_US',
  }) async {
    if (!_ready) {
      final ok = await initialize();
      if (!ok) return;
    }
    await _listenWithFallback(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        partialResults: true,
        localeId: localeId,
      ),
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) onFinal(result.recognizedWords);
      },
    );
  }

  Future<void> stopListening() async {
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {
      // No speech engine — nothing to stop.
    }
  }

  /// Starts the background trigger loop. Returns false when the
  /// microphone / recogniser is unavailable. [onTriggerCommand] runs
  /// for every command heard after "Hello Ayra"; [onTriggerOnly] runs
  /// when the user says just "Hello Ayra" (the next sentence within
  /// 10 seconds is then treated as the command). [onPartialTranscript]
  /// reports live partial transcripts so the UI can show them.
  /// [onLoopEvent] reports loop state changes (listening / failed /
  /// heard / fallback) for diagnostics. The loop never stops itself —
  /// only [stopTriggerLoop] (the user's OFF) ends it.
  Future<bool> startTriggerLoop({
    required void Function(String command) onTriggerCommand,
    required void Function() onTriggerOnly,
    void Function(String text)? onPartialTranscript,
    void Function(LoopEvent event)? onLoopEvent,
    String localeId = 'en-US',
  }) async {
    if (_loopActive) return true;
    if (!_ready) {
      // Background isolate: only check the mic status, never request
      // it here — no permission dialog can appear in this isolate.
      // The ON flow grants the mic in the UI before starting.
      final ok = await initialize(requestPermission: false);
      if (!ok) return false;
    }
    _loopActive = true;
    _loopFailures = 0;
    _errorTracker.reset();
    _loopLocale = localeId;
    _awaitingCommandUntil = null;
    _onTriggerCommand = onTriggerCommand;
    _onTriggerOnly = onTriggerOnly;
    _onPartialTranscript = onPartialTranscript;
    _onLoopEvent = onLoopEvent;
    _onDeviceUnavailable = false;
    _lastActivity = DateTime.now();
    _startWatchdog();
    await _listenOnce();
    return true;
  }

  /// Stops the trigger loop completely. Never throws.
  Future<void> stopTriggerLoop() async {
    _loopActive = false;
    _loopRestartTimer?.cancel();
    _loopRestartTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _onTriggerCommand = null;
    _onTriggerOnly = null;
    _onPartialTranscript = null;
    _onLoopEvent = null;
    _awaitingCommandUntil = null;
    await stopListening();
  }

  /// Restarts the loop's current listen session (fresh window).
  /// Used when the user taps the floating mic button.
  Future<void> restartTriggerLoop() async {
    if (!_loopActive) return;
    _loopRestartTimer?.cancel();
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
    await _listenOnce();
  }

  /// Watches for a wedged recogniser: if nothing (no status, result or
  /// error) arrives for 15 seconds while the loop is active, the session
  /// is force-restarted. Also restarts when the loop is idle with no
  /// session running and no restart pending (for example a session that
  /// failed to start at all).
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_loopActive) return;
      final idle = DateTime.now().difference(_lastActivity);
      final restartPending = _loopRestartTimer?.isActive ?? false;
      if (!_speech.isListening && !restartPending && idle > const Duration(seconds: 5)) {
        _forceRestartLoop();
        return;
      }
      if (idle > const Duration(seconds: 15)) {
        _forceRestartLoop();
      }
    });
  }

  Future<void> _forceRestartLoop() async {
    if (!_loopActive) return;
    _lastActivity = DateTime.now();
    _loopRestartTimer?.cancel();
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
    await _listenOnce();
  }

  /// Listens once, preferring on-device recognition and falling back to
  /// cloud recognition when the locale has no on-device model.
  /// speech_to_text 7.x `listen()` returns no bool (it resolves to null),
  /// so a failed start is detected by the watchdog instead.
  Future<void> _listenWithFallback({
    required SpeechListenOptions listenOptions,
    required void Function(SpeechRecognitionResult result) onResult,
  }) async {
    try {
      await _speech.listen(listenOptions: listenOptions, onResult: onResult);
    } catch (_) {
      // The session could not start at all (for example no on-device
      // model for this locale) — retry once with cloud recognition.
      if (listenOptions.onDevice) {
        _onDeviceUnavailable = true;
        try {
          await _speech.listen(
            listenOptions: listenOptions.copyWith(onDevice: false),
            onResult: onResult,
          );
        } catch (_) {
          // Still failing — the watchdog / error handler retries.
        }
      }
    }
  }

  Future<void> _listenOnce() async {
    if (!_loopActive) return;
    _lastActivity = DateTime.now();
    await _listenWithFallback(
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        localeId: _loopLocale,
        listenFor: const Duration(seconds: 120),
        pauseFor: const Duration(seconds: 3),
        onDevice: !_onDeviceUnavailable,
      ),
      onResult: (result) {
        if (!_loopActive) return;
        _lastActivity = DateTime.now();
        if (result.finalResult) {
          _handleFinalTranscript(result.recognizedWords);
        } else {
          _onPartialTranscript?.call(result.recognizedWords);
        }
      },
    );
  }

  void _handleFinalTranscript(String text) {
    if (!_loopActive) return;
    _loopFailures = 0;
    _errorTracker.noteSuccess();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _scheduleLoopRestart();
      return;
    }
    _onLoopEvent?.call(LoopEvent(LoopEventKind.heard, trimmed));
    final command = extractCommandAfterTrigger(trimmed);
    if (command != null) {
      if (command.isEmpty) {
        // Just "Hello Ayra" — wait up to 10 seconds for the command.
        _awaitingCommandUntil =
            DateTime.now().add(const Duration(seconds: 10));
        _onTriggerOnly?.call();
      } else {
        _awaitingCommandUntil = null;
        _onTriggerCommand?.call(command);
      }
      // Give the reply a moment before listening again.
      _scheduleLoopRestart(delay: const Duration(milliseconds: 1500));
      return;
    }
    if (_awaitingCommandUntil != null &&
        DateTime.now().isBefore(_awaitingCommandUntil!)) {
      _awaitingCommandUntil = null;
      _onTriggerCommand?.call(trimmed);
      _scheduleLoopRestart(delay: const Duration(milliseconds: 1500));
      return;
    }
    // No trigger — ignore the sentence and keep listening.
    _scheduleLoopRestart();
  }

  void _scheduleLoopRestart({Duration? delay}) {
    if (!_loopActive) return;
    _loopRestartTimer?.cancel();
    _loopRestartTimer = Timer(
      delay ?? const Duration(milliseconds: 600),
      () {
        if (!_loopActive) return;
        _listenOnce();
      },
    );
  }

  /// A real recogniser failure (no network, no mic, no engine, language
  /// missing, recogniser busy). Backs off and retries — the loop never
  /// stops itself, only the user's OFF stops it.
  void _noteLoopFailure(String errorMsg) {
    if (!_loopActive) return;
    // No on-device model for this locale — fall back to cloud next time.
    if ((errorMsg == 'error_language_not_supported' ||
            errorMsg == 'error_language_unavailable') &&
        !_onDeviceUnavailable) {
      _onDeviceUnavailable = true;
    }
    _loopFailures++;
    final backoffMs = (500 * (1 << (_loopFailures - 1))).clamp(500, 30000);
    _scheduleLoopRestart(delay: Duration(milliseconds: backoffMs));
  }

  /// Speaks [text] out loud. [language] is 'en', 'roman' or 'ur'.
  /// Roman Urdu is spoken with the English voice (no Roman Urdu voice
  /// exists on devices); Urdu script uses the Urdu voice when installed.
  /// Never throws — on a device without TTS it simply stays silent.
  Future<void> speak(String text, String language) async {
    try {
      // In loop mode the recogniser session already ended on the final
      // result — do not stop it again, the loop restarts it itself.
      if (!_loopActive) await _speech.stop();
      final locale = language == 'ur' ? 'ur-PK' : 'en-US';
      await _tts.setLanguage(locale);
      await _tts.speak(text);
    } catch (_) {
      // No TTS on this device — the written reply still shows.
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop.
    }
  }
}

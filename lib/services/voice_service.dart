import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// On-device speech recognition and speech synthesis.
/// Both are free and need no API key. Speech recognition uses the
/// device's own engine (Google on Android, Microsoft on Windows);
/// TTS uses the device's installed voices.
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;

  /// Initialises speech recognition and the TTS engine.
  /// Returns true when listening is available. Never throws — on a
  /// device without speech support it simply returns false.
  Future<bool> initialize() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isDenied || status.isPermanentlyDenied) return false;
      _ready = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
      await _tts.setSpeechRate(0.95);
      await _tts.setVolume(1.0);
      return _ready;
    } catch (_) {
      return false;
    }
  }

  bool get isListening => _speech.isListening;

  /// Starts listening. Calls [onResult] with the recognised words as
  /// they arrive, and [onFinal] once with the final sentence.
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String text) onFinal,
    String localeId = 'en_US',
  }) async {
    if (!_ready) {
      final ok = await initialize();
      if (!ok) return;
    }
    await _speech.listen(
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

  /// Speaks [text] out loud. [language] is 'en', 'roman' or 'ur'.
  /// Roman Urdu is spoken with the English voice (no Roman Urdu voice
  /// exists on devices); Urdu script uses the Urdu voice when installed.
  /// Never throws — on a device without TTS it simply stays silent.
  Future<void> speak(String text, String language) async {
    try {
      await _speech.stop();
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

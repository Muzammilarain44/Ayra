import 'package:ayra/services/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyLoopError', () {
    test('silence errors are not failures', () {
      expect(classifyLoopError('error_no_match'), LoopErrorKind.silence);
      expect(
        classifyLoopError('error_speech_timeout'),
        LoopErrorKind.silence,
      );
      expect(classifyLoopError('error_client'), LoopErrorKind.silence);
    });

    test('real failures count', () {
      expect(classifyLoopError('error_network'), LoopErrorKind.realFailure);
      expect(classifyLoopError('error_server'), LoopErrorKind.realFailure);
      expect(classifyLoopError('error_audio'), LoopErrorKind.realFailure);
      expect(
        classifyLoopError('error_insufficient_permissions'),
        LoopErrorKind.realFailure,
      );
      expect(
        classifyLoopError('error_recognizer_busy'),
        LoopErrorKind.realFailure,
      );
      expect(
        classifyLoopError('error_language_not_supported'),
        LoopErrorKind.realFailure,
      );
      expect(classifyLoopError('error_unknown'), LoopErrorKind.realFailure);
    });
  });

  group('LoopErrorTracker — the error_client trap', () {
    test('three errors with no success ever triggers a fallback', () {
      final tracker = LoopErrorTracker();
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isTrue);
    });

    test('a single error after a success never triggers a fallback', () {
      final tracker = LoopErrorTracker();
      tracker.noteSuccess();
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isFalse);
      // The streak resets on every success, so even many errors
      // spread across successful sessions never fall back.
      tracker.noteSuccess();
      expect(tracker.noteError(), isFalse);
    });

    test('reset starts a fresh run with no successes', () {
      final tracker = LoopErrorTracker();
      tracker.noteSuccess();
      tracker.reset();
      expect(tracker.hadSuccessfulSession, isFalse);
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isFalse);
      expect(tracker.noteError(), isTrue);
    });
  });
}

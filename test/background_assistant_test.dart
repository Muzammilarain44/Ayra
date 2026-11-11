import 'package:ayra/services/background_assistant.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('classifyStartError — the start failure must name its reason',
      () {
    test('plugin timeout maps to timeout', () {
      expect(
        classifyStartError(ServiceTimeoutException()),
        AssistantStartFailure.timeout,
      );
    });

    test('already-started maps to alreadyRunning', () {
      expect(
        classifyStartError(ServiceAlreadyStartedException()),
        AssistantStartFailure.alreadyRunning,
      );
    });

    test('background start refusal maps to backgroundStart', () {
      expect(
        classifyStartError(
          PlatformException(
            code: 'error',
            message:
                'ForegroundServiceStartNotAllowedException: Not allowed to start service',
          ),
        ),
        AssistantStartFailure.backgroundStart,
      );
    });

    test('SecurityException without RECORD_AUDIO maps to microphoneDenied',
        () {
      expect(
        classifyStartError(
          PlatformException(
            code: 'error',
            message:
                'java.lang.SecurityException: Starting FGS with type microphone requires RECORD_AUDIO permission',
          ),
        ),
        AssistantStartFailure.microphoneDenied,
      );
    });

    test('anything else maps to unknown', () {
      expect(
        classifyStartError(Exception('boom')),
        AssistantStartFailure.unknown,
      );
    });
  });

  group('AssistantStartResult', () {
    test('ok has no failure', () {
      const result = AssistantStartResult.ok();
      expect(result.isOk, isTrue);
      expect(result.failure, isNull);
    });

    test('failed carries its reason', () {
      const result = AssistantStartResult.failed(
        AssistantStartFailure.microphoneDenied,
      );
      expect(result.isOk, isFalse);
      expect(result.failure, AssistantStartFailure.microphoneDenied);
    });
  });

  group('AyraTaskHandler.onStart — a failure must surface, never die '
      'silently', () {
    test('loop that cannot start reports a failed diagnostic', () async {
      // No native plugins exist in flutter_test, so the trigger loop
      // cannot start here — exactly the situation that used to die
      // silently. onStart must not throw and must report it.
      SharedPreferences.setMockInitialValues({});
      final reported = <Map<String, Object>>[];
      final handler = AyraTaskHandler(diagnosticSink: reported.add);
      try {
        await handler.onStart(DateTime.now(), TaskStarter.developer);
      } finally {
        // Cancel the 30s retry timer armed by the failed start.
        await handler.onDestroy(DateTime.now(), false);
      }
      final failures = reported.where(
        (m) => m['type'] == 'diagnostic' && m['state'] == 'failed',
      );
      expect(
        failures,
        isNotEmpty,
        reason: 'onStart must surface the loop failure, not swallow it',
      );
      expect(
        failures.first['detail'].toString(),
        contains('Loop could not start'),
      );
    });
  });
}

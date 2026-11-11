import 'package:ayra/services/microphone_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('micGateDecision — the ON flow must ask for the mic before start',
      () {
    test('granted mic proceeds straight to start', () {
      expect(micGateDecision(PermissionStatus.granted), MicGate.proceed);
    });

    test('denied mic asks once (fresh install)', () {
      expect(micGateDecision(PermissionStatus.denied), MicGate.request);
    });

    test('permanently denied mic goes to Settings, never to start', () {
      expect(
        micGateDecision(PermissionStatus.permanentlyDenied),
        MicGate.openSettings,
      );
    });

    test('restricted mic goes to Settings, never to start', () {
      expect(
        micGateDecision(PermissionStatus.restricted),
        MicGate.openSettings,
      );
    });
  });
}

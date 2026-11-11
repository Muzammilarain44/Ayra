import 'package:ayra/services/background_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssistantMode', () {
    test('starts OFF by default', () {
      expect(AssistantMode().isOn, false);
    });

    test('turnOn and turnOff switch the state', () {
      final mode = AssistantMode();
      mode.turnOn();
      expect(mode.isOn, true);
      mode.turnOn();
      expect(mode.isOn, true);
      mode.turnOff();
      expect(mode.isOn, false);
      mode.turnOff();
      expect(mode.isOn, false);
    });

    test('restores from a saved value, null means OFF', () {
      expect(AssistantMode.fromSaved(true).isOn, true);
      expect(AssistantMode.fromSaved(false).isOn, false);
      expect(AssistantMode.fromSaved(null).isOn, false);
    });
  });
}

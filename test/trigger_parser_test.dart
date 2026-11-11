import 'package:ayra/services/trigger_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractCommandAfterTrigger', () {
    test('strips "Hello Ayra" and returns the command', () {
      expect(
        extractCommandAfterTrigger('Hello Ayra open WhatsApp'),
        'open whatsapp',
      );
      expect(
        extractCommandAfterTrigger('hello ayra what time is it'),
        'what time is it',
      );
    });

    test('is case-insensitive and ignores commas', () {
      expect(
        extractCommandAfterTrigger('HELLO AYRA, OPEN YOUTUBE'),
        'open youtube',
      );
      expect(
        extractCommandAfterTrigger('Hello, Ayra set alarm 7 AM'),
        'set alarm 7 am',
      );
    });

    test('returns empty string for trigger only', () {
      expect(extractCommandAfterTrigger('Hello Ayra'), '');
      expect(extractCommandAfterTrigger('hello ayra'), '');
    });

    test('accepts common mishearings of the name', () {
      expect(
        extractCommandAfterTrigger('hello aira open camera'),
        'open camera',
      );
      expect(
        extractCommandAfterTrigger('hey ayra tell me a joke'),
        'tell me a joke',
      );
    });

    test('accepts "era / ara / ayrah" and "hallo / halo" mishearings', () {
      expect(
        extractCommandAfterTrigger('hello era open whatsapp'),
        'open whatsapp',
      );
      expect(
        extractCommandAfterTrigger('hallo ayra what time is it'),
        'what time is it',
      );
      expect(
        extractCommandAfterTrigger('halo ara open youtube'),
        'open youtube',
      );
      expect(
        extractCommandAfterTrigger('hey ayrah tell me a joke'),
        'tell me a joke',
      );
      expect(
        extractCommandAfterTrigger('hello ara set alarm 7 am'),
        'set alarm 7 am',
      );
    });

    test('accepts "aera / ayraa / eraa" and "helo" mishearings', () {
      expect(
        extractCommandAfterTrigger('hello aera open whatsapp'),
        'open whatsapp',
      );
      expect(
        extractCommandAfterTrigger('hello ayraa what time is it'),
        'what time is it',
      );
      expect(
        extractCommandAfterTrigger('helo ayra open youtube'),
        'open youtube',
      );
      expect(
        extractCommandAfterTrigger('hello eraa tell me a joke'),
        'tell me a joke',
      );
      expect(
        extractCommandAfterTrigger('helo aera set alarm 7 am'),
        'set alarm 7 am',
      );
    });

    test('loose match: greeting and name need not be adjacent', () {
      expect(
        extractCommandAfterTrigger('hello my ayra open whatsapp'),
        'open whatsapp',
      );
      expect(
        extractCommandAfterTrigger('hello there ayra what time is it'),
        'what time is it',
      );
    });

    test('returns null when there is no trigger', () {
      expect(extractCommandAfterTrigger('open YouTube'), null);
      expect(extractCommandAfterTrigger('what is the weather'), null);
      expect(extractCommandAfterTrigger(''), null);
    });

    test('finds the trigger in the middle of a sentence', () {
      expect(
        extractCommandAfterTrigger('please hello ayra open google'),
        'open google',
      );
    });
  });

  group('isTriggerOnly', () {
    test('true for trigger alone', () {
      expect(isTriggerOnly('Hello Ayra'), true);
    });

    test('false when a command follows', () {
      expect(isTriggerOnly('Hello Ayra open WhatsApp'), false);
    });

    test('false when there is no trigger', () {
      expect(isTriggerOnly('open WhatsApp'), false);
    });
  });
}

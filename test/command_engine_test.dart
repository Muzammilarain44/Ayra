import 'package:ayra/calculator.dart';
import 'package:ayra/command_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Calculator', () {
    test('adds, subtracts, multiplies, divides', () {
      expect(Calculator.evaluate('12 + 8'), 20);
      expect(Calculator.evaluate('20 - 5'), 15);
      expect(Calculator.evaluate('6 * 7'), 42);
      expect(Calculator.evaluate('20 / 4'), 5);
    });
    test('respects brackets and precedence', () {
      expect(Calculator.evaluate('(2 + 3) * 4'), 20);
      expect(Calculator.evaluate('2 + 3 * 4'), 14);
      expect(Calculator.evaluate('2 ^ 3'), 8);
      expect(Calculator.evaluate('10 % 3'), 1);
    });
    test('handles decimals and unary minus', () {
      expect(Calculator.evaluate('2.5 * 4'), 10);
      expect(Calculator.evaluate('-5 + 3'), -2);
    });
    test('rejects bad input safely', () {
      expect(() => Calculator.evaluate('12 / 0'), throwsFormatException);
      expect(() => Calculator.evaluate('2 +'), throwsFormatException);
      expect(() => Calculator.evaluate('hello'), throwsFormatException);
    });
    test('formats results cleanly', () {
      expect(Calculator.format(4.0), '4');
      expect(Calculator.format(2.5), '2.5');
    });
  });

  group('CommandEngine — English', () {
    test('greets', () {
      final engine = CommandEngine();
      final result = engine.handle('hello');
      expect(result.action, CommandAction.greeting);
      expect(result.language, 'en');
    });
    test('does not greet on "this"', () {
      final engine = CommandEngine();
      final result = engine.handle('what is this');
      expect(result.action, isNot(CommandAction.greeting));
    });
    test('opens YouTube', () {
      final engine = CommandEngine();
      final result = engine.handle('open YouTube');
      expect(result.action, CommandAction.openSite);
      expect(result.data, 'https://www.youtube.com');
    });
    test('searches YouTube', () {
      final engine = CommandEngine();
      final result = engine.handle('search cats on youtube');
      expect(result.action, CommandAction.searchWeb);
      expect(result.data, contains('youtube.com/results'));
      expect(result.data, contains('cats'));
    });
    test('tells the time with a fixed clock', () {
      final engine = CommandEngine();
      final result = engine.handle(
        'what time is it',
        now: DateTime(2026, 11, 9, 15, 30),
      );
      expect(result.action, CommandAction.tellTime);
      expect(result.reply, contains('3:30 PM'));
    });
    test('tells the date', () {
      final engine = CommandEngine();
      final result = engine.handle(
        'what is the date today',
        now: DateTime(2026, 11, 9),
      );
      expect(result.action, CommandAction.tellDate);
      expect(result.reply, contains('9 November 2026'));
    });
    test('calculates inline expressions', () {
      final engine = CommandEngine();
      expect(engine.handle('12 + 8').reply, contains('20'));
      expect(engine.handle('calculate 15 * 4').reply, contains('60'));
      expect(engine.handle('(2 + 3) * 4').reply, contains('20'));
    });
    test('refuses divide by zero politely', () {
      final engine = CommandEngine();
      final result = engine.handle('calculate 5 / 0');
      expect(result.action, CommandAction.calculate);
      expect(result.reply.toLowerCase(), contains('cannot divide'));
    });
    test('remembers, recalls and forgets', () {
      final engine = CommandEngine();
      engine.handle('remember my name is Muzammil');
      expect(engine.memories['name'], 'Muzammil');
      final recall = engine.handle('what is my name');
      expect(recall.action, CommandAction.recall);
      expect(recall.reply, contains('Muzammil'));
      engine.handle('forget my name');
      expect(engine.memories.containsKey('name'), isFalse);
    });
    test('adds, lists and clears notes', () {
      final engine = CommandEngine();
      engine.handle('note buy milk');
      expect(engine.notes, ['buy milk']);
      final listed = engine.handle('show my notes');
      expect(listed.reply, contains('buy milk'));
      engine.handle('clear notes');
      expect(engine.notes, isEmpty);
    });
    test('sets a timer with a label', () {
      final engine = CommandEngine();
      final result = engine.handle('remind me in 10 minutes to call Ali');
      expect(result.action, CommandAction.timerSet);
      expect(result.data, '600|call Ali');
    });
    test('converts units', () {
      final engine = CommandEngine();
      final km = engine.handle('convert 5 km to miles');
      expect(km.action, CommandAction.convert);
      expect(km.reply, contains('3.10686'));
      final temp = engine.handle('convert 100 c to f');
      expect(temp.reply, contains('212'));
    });
    test('generates a 16-character password', () {
      final engine = CommandEngine();
      final result = engine.handle('generate password');
      expect(result.action, CommandAction.password);
      expect(result.data, isNotNull);
      expect(result.data!.length, 16);
    });
    test('dials a number', () {
      final engine = CommandEngine();
      final result = engine.handle('call 03303094425');
      expect(result.action, CommandAction.dial);
      expect(result.data, 'tel:03303094425');
    });
    test('answers help and about', () {
      final engine = CommandEngine();
      expect(engine.handle('help').action, CommandAction.help);
      expect(engine.handle('who are you').action, CommandAction.about);
    });
    test('falls back politely on unknown input', () {
      final engine = CommandEngine();
      final result = engine.handle('blablabla zzz');
      expect(result.action, CommandAction.unknown);
    });
    test('windows actions are recognised', () {
      final engine = CommandEngine();
      expect(
        engine.handle('organize desktop').action,
        CommandAction.windowsOrganize,
      );
      expect(
        engine.handle('empty recycle bin').action,
        CommandAction.windowsRecycleBin,
      );
      expect(
        engine.handle('shutdown pc').action,
        CommandAction.windowsShutdown,
      );
      expect(engine.handle('lock pc').action, CommandAction.windowsLock);
    });
  });

  group('CommandEngine — Roman Urdu', () {
    test('opens YouTube in Roman Urdu', () {
      final engine = CommandEngine();
      final result = engine.handle('YouTube kholo');
      expect(result.action, CommandAction.openSite);
      expect(result.language, 'roman');
    });
    test('tells the time in Roman Urdu', () {
      final engine = CommandEngine();
      final result = engine.handle(
        'time kya hai',
        now: DateTime(2026, 11, 9, 9, 5),
      );
      expect(result.action, CommandAction.tellTime);
      expect(result.reply, contains('9:05 AM'));
    });
    test('remembers and recalls in Roman Urdu', () {
      final engine = CommandEngine();
      engine.handle('yaad rakho mera naam Muzammil hai');
      expect(engine.memories['naam'], 'Muzammil');
      final recall = engine.handle('mera naam kya hai');
      expect(recall.reply, contains('Muzammil'));
    });
    test('sets a timer in Roman Urdu', () {
      final engine = CommandEngine();
      final result = engine.handle('5 minute ka timer lagao');
      expect(result.action, CommandAction.timerSet);
      expect(result.data, '300|Timer');
    });
  });

  group('CommandEngine — new no-API features', () {
    test('opens installed apps by name', () {
      final engine = CommandEngine();
      final chrome = engine.handle('open Chrome');
      expect(chrome.action, CommandAction.openApp);
      expect(chrome.data, 'Chrome');
      expect(engine.handle('camera kholo').action, CommandAction.openCamera);
      expect(
        engine.handle('settings kholo').action,
        CommandAction.openSettings,
      );
      expect(engine.handle('wifi settings kholo').data, 'wifi');
      expect(engine.handle('bluetooth kholo').data, 'bluetooth');
    });
    test('sets an alarm', () {
      final engine = CommandEngine();
      expect(engine.handle('set alarm 7 AM').data, '7|0|');
      expect(engine.handle('alarm 6:30 PM').data, '18|30|');
      expect(
        engine.handle('7 baje ka alarm lagao').action,
        CommandAction.setAlarm,
      );
    });
    test('controls volume', () {
      final engine = CommandEngine();
      expect(engine.handle('volume up').action, CommandAction.volumeUp);
      expect(
        engine.handle('volume kam karo').action,
        CommandAction.volumeDown,
      );
      expect(engine.handle('mute karo').action, CommandAction.volumeMute);
      expect(engine.handle('unmute').action, CommandAction.volumeUnmute);
    });
    test('tosses a coin and rolls dice', () {
      final engine = CommandEngine();
      final coin = engine.handle('coin toss karo');
      expect(coin.action, CommandAction.coinToss);
      expect(coin.reply, isNotEmpty);
      final dice = engine.handle('dice roll karo');
      expect(dice.action, CommandAction.diceRoll);
      expect(dice.reply, contains(RegExp(r'[1-6]')));
    });
    test('runs a stopwatch', () {
      final engine = CommandEngine();
      final start = engine.handle(
        'stopwatch start karo',
        now: DateTime(2026, 11, 9, 10, 0, 0),
      );
      expect(start.action, CommandAction.stopwatchStart);
      final stop = engine.handle(
        'stopwatch band karo',
        now: DateTime(2026, 11, 9, 10, 1, 5),
      );
      expect(stop.action, CommandAction.stopwatchStop);
      expect(stop.reply, contains('1 minute 5 seconds'));
    });
    test('closes itself on request', () {
      final engine = CommandEngine();
      expect(engine.handle('Ayra band karo').action, CommandAction.closeApp);
      expect(engine.handle('app band karo').action, CommandAction.closeApp);
    });
  });

  group('CommandEngine — Urdu script', () {
    test('opens YouTube in Urdu script', () {
      final engine = CommandEngine();
      final result = engine.handle('یوٹیوب کھولو');
      expect(result.action, CommandAction.openSite);
      expect(result.language, 'ur');
    });
    test('tells the time in Urdu script', () {
      final engine = CommandEngine();
      final result = engine.handle(
        'وقت کیا ہے',
        now: DateTime(2026, 11, 9, 18, 45),
      );
      expect(result.action, CommandAction.tellTime);
      expect(result.reply, contains('6:45 PM'));
    });
    test('remembers in Urdu script', () {
      final engine = CommandEngine();
      engine.handle('یاد رکھو میرا نام مزمل ہے');
      expect(engine.memories['نام'], 'مزمل');
      final recall = engine.handle('میرا نام کیا ہے');
      expect(recall.reply, contains('مزمل'));
    });
  });
}

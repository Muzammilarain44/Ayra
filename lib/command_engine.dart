import 'dart:math';

import 'calculator.dart';

/// What Ayra understood a command to be. The UI turns an action into
/// real work (opening a link, reading the battery, speaking, ...).
enum CommandAction {
  greeting,
  help,
  about,
  openSite,
  searchWeb,
  dial,
  sms,
  tellTime,
  tellDate,
  calculate,
  noteAdd,
  noteList,
  noteClear,
  remember,
  recall,
  forget,
  timerSet,
  joke,
  quote,
  convert,
  password,
  battery,
  torchOn,
  torchOff,
  openApp,
  openCamera,
  setAlarm,
  openSettings,
  volumeUp,
  volumeDown,
  volumeMute,
  volumeUnmute,
  coinToss,
  diceRoll,
  stopwatchStart,
  stopwatchStop,
  closeApp,
  windowsOrganize,
  windowsRecycleBin,
  windowsShutdown,
  windowsLock,
  unknown,
}

/// The engine's answer: what to do, what to say, and optional data
/// (a URL, a number of seconds, a generated password, ...).
class CommandResult {
  const CommandResult({
    required this.action,
    required this.reply,
    this.data,
    required this.language,
  });

  final CommandAction action;
  final String reply;
  final String? data;

  /// 'en', 'roman' (Roman Urdu) or 'ur' (Urdu script).
  final String language;
}

/// Pure-Dart rule engine: no plugins, no network, fully unit-testable.
/// Understands English, Roman Urdu and Urdu script.
class CommandEngine {
  CommandEngine({Map<String, String>? memories, List<String>? notes})
      : memories = memories ?? {},
        notes = notes ?? [];

  /// Remembered facts, keyed by a normalised lowercase key.
  final Map<String, String> memories;

  /// Notes, newest last.
  final List<String> notes;

  CommandResult handle(String rawInput, {DateTime? now}) {
    final input = rawInput.trim();
    final time = now ?? DateTime.now();
    final lang = _detectLanguage(input);
    final lower = input.toLowerCase();
    final norm = _normalise(lower);

    String t(String en, String roman, String ur) {
      if (lang == 'ur') return ur;
      if (lang == 'roman') return roman;
      return en;
    }

    if (input.isEmpty) {
      return CommandResult(
        action: CommandAction.help,
        reply: t(
          "Say or type something — for example 'open YouTube', 'what time is it', or 'calculate 12 + 8'.",
          "Kuch bolo ya likho — jaise 'YouTube kholo', 'time kya hai', ya '12 + 8 calculate karo'.",
          "کچھ بولیں یا لکھیں — جیسے 'یوٹیوب کھولو'، 'وقت کیا ہے'، یا '12 + 8 حساب کرو'۔",
        ),
        language: lang,
      );
    }

    // ---- Greeting (word-boundary match: "hi" must not fire inside "this") ----
    if (RegExp(r'\b(salam|aoa|assalam|hello|hi|hey|salaam|adaab)\b')
            .hasMatch(norm) ||
        _containsAny(norm, ['السلام', 'ہیلو', 'سلام'])) {
      return CommandResult(
        action: CommandAction.greeting,
        reply: t(
          "Hello! I'm Ayra, your free voice assistant. How can I help?",
          "Salam! Main Ayra hun, tumhari free voice assistant. Kya karun tumhare liye?",
          "سلام! میں ایرا ہوں، آپ کی مفت وائس اسسٹنٹ۔ میں آپ کی کیا مدد کر سکتی ہوں؟",
        ),
        language: lang,
      );
    }

    // ---- Help ----
    if (_containsAny(norm, [
      'help', 'madad', 'kya kar sakti ho', 'kya kar sakte ho', 'commands',
      'مدد', 'کیا کر سکتی ہو',
    ])) {
      return CommandResult(
        action: CommandAction.help,
        reply: t(
          "I can open sites (YouTube, Google, GitHub, WhatsApp), tell the time and date, calculate, keep notes, remember things, set timers, tell jokes, convert units, make passwords, check battery, and on Windows organise the desktop, empty the Recycle Bin, lock or shut down the PC. I can also open any installed app by name, open the camera, set alarms, open WiFi or Bluetooth settings, change the volume, toss a coin, roll dice, run a stopwatch, and close myself. Try 'open Chrome' or 'set alarm 7 AM'.",
          "Main sites khol sakti hun (YouTube, Google, GitHub, WhatsApp), time aur date bata sakti hun, hisaab kar sakti hun, notes rakh sakti hun, cheezein yaad rakh sakti hun, timer laga sakti hun, jokes suna sakti hun, units convert kar sakti hun, password bana sakti hun, battery check kar sakti hun, aur Windows par desktop organize, Recycle Bin khali, PC lock ya shutdown kar sakti hun. Main kisi bhi installed app ko naam se khol sakti hun, camera khol sakti hun, alarm laga sakti hun, WiFi ya Bluetooth settings khol sakti hun, volume badal sakti hun, sikka uchal sakti hun, pansa phenk sakti hun, stopwatch chala sakti hun, aur khud band ho sakti hun. Try karo: 'Chrome kholo' ya '7 baje ka alarm lagao'.",
          "میں سائٹس کھول سکتی ہوں (یوٹیوب، گوگل، گٹ ہب، واٹس ایپ)، وقت اور تاریخ بتا سکتی ہوں، حساب کر سکتی ہوں، نوٹس رکھ سکتی ہوں، چیزیں یاد رکھ سکتی ہوں، ٹائمر لگا سکتی ہوں، لطیفے سنا سکتی ہوں، یونٹس تبدیل کر سکتی ہوں، پاس ورڈ بنا سکتی ہوں، بیٹری چیک کر سکتی ہوں، اور ونڈوز پر ڈیسک ٹاپ ترتیب دے سکتی ہوں، ری سائیکل بن خالی کر سکتی ہوں، پی سی لاک یا بند کر سکتی ہوں۔ میں کسی بھی انسٹال شدہ ایپ کو نام سے کھول سکتی ہوں، کیمرہ کھول سکتی ہوں، الارم لگا سکتی ہوں، وائی فائی یا بلوٹوتھ سیٹنگز کھول سکتی ہوں، آواز بدل سکتی ہوں، سکہ اچھال سکتی ہوں، پانسہ پھینک سکتی ہوں، سٹاپ واچ چلا سکتی ہوں، اور خود بند ہو سکتی ہوں۔ آزمائیں: 'کروم کھولو' یا '7 بجے کا الارم لگاؤ'۔",
        ),
        language: lang,
      );
    }

    // ---- Who are you ----
    if (_containsAny(norm, [
      'who are you', 'tum kaun ho', 'tumhara naam', 'apna naam',
      'تم کون ہو', 'تمہارا نام',
    ])) {
      return CommandResult(
        action: CommandAction.about,
        reply: t(
          "I'm Ayra — a free voice assistant built by Muzammil. I work on your device, I need no paid API, and I never send your data anywhere.",
          "Main Ayra hun — Muzammil ki banayi hui free voice assistant. Main tumhare device par kaam karti hun, mujhe koi paid API nahi chahiye, aur tumhara data kahin nahi bhejti.",
          "میں ایرا ہوں — مزمل کی بنائی ہوئی مفت وائس اسسٹنٹ۔ میں آپ کے آلے پر کام کرتی ہوں، مجھے کوئی پےڈ API نہیں چاہیے، اور آپ کا ڈیٹا کہیں نہیں بھیجتی۔",
        ),
        language: lang,
      );
    }

    // ---- Time & date ----
    if ((_hasWord(norm, 'time') ||
            _containsAny(norm, ['waqt', 'baj', 'وقت', 'بج'])) &&
        !_containsAny(norm, ['timer', 'alarm', 'الارم'])) {
      return CommandResult(
        action: CommandAction.tellTime,
        reply: t(
          'It is ${_formatTime(time)}.',
          'Abhi ${_formatTime(time)} baj rahe hain.',
          'ابھی ${_formatTime(time)} بج رہے ہیں۔',
        ),
        language: lang,
      );
    }
    if (_hasWord(norm, 'date') ||
        _containsAny(norm, ['tareekh', 'تاریخ', 'آج']) ||
        _hasWord(norm, 'aaj')) {
      return CommandResult(
        action: CommandAction.tellDate,
        reply: t(
          'Today is ${_formatDate(time)}.',
          'Aaj ${_formatDate(time)} hai.',
          'آج ${_formatDate(time)} ہے۔',
        ),
        language: lang,
      );
    }

    // ---- Timer / reminder ----
    final timer = _parseTimer(norm, input);
    if (timer != null) {
      final seconds = timer.$1;
      final label = timer.$2;
      final human = _humanDuration(seconds, lang);
      return CommandResult(
        action: CommandAction.timerSet,
        data: '$seconds|${label.isEmpty ? 'Timer' : label}',
        reply: t(
          'Timer set for $human${label.isEmpty ? '' : ' — $label'}.',
          '$human ka timer laga diya${label.isEmpty ? '' : ' — $label'}.',
          '$human کا ٹائمر لگا دیا گیا${label.isEmpty ? '' : ' — $label'}۔',
        ),
        language: lang,
      );
    }

    // ---- Alarm (opens the system clock's alarm screen) ----
    final alarm = _parseAlarm(norm);
    if (alarm != null) {
      final hour = alarm.$1;
      final minute = alarm.$2;
      final label = alarm.$3;
      final hm = _formatTime(DateTime(2026, 1, 1, hour, minute));
      return CommandResult(
        action: CommandAction.setAlarm,
        data: '$hour|$minute|$label',
        reply: t(
          'Setting an alarm for $hm.',
          '$hm ka alarm laga rahi hun.',
          '$hm کا الارم لگا رہی ہوں۔',
        ),
        language: lang,
      );
    }

    // ---- Calculator ----
    if (_containsAny(norm, ['calculate', 'calc', 'hisaab', 'hisab', 'حساب'])) {
      final expr = _extractExpression(norm);
      if (expr != null) {
        return _calculate(expr, lang, t);
      }
    } else {
      final expr = _extractExpression(norm);
      if (expr != null) return _calculate(expr, lang, t);
    }

    // ---- Unit converter ----
    final converted = _tryConvert(norm, lang, t);
    if (converted != null) return converted;

    // ---- Password generator ----
    if (_containsAny(norm, [
      'generate password', 'password banao', 'password bana', 'new password',
      'پاس ورڈ بناؤ',
    ])) {
      final password = _generatePassword();
      return CommandResult(
        action: CommandAction.password,
        data: password,
        reply: t(
          'Here is a strong password: $password. Keep it safe.',
          'Ye lo mazboot password: $password. Ise mehfooz rakho.',
          'یہ رہا مضبوط پاس ورڈ: $password۔ اسے محفوظ رکھیں۔',
        ),
        language: lang,
      );
    }

    // ---- Battery ----
    if (_containsAny(norm, ['battery', 'charge', 'بیٹری', 'چارج'])) {
      return CommandResult(
        action: CommandAction.battery,
        reply: t('Checking battery…', 'Battery check kar rahi hun…',
            'بیٹری چیک کر رہی ہوں…'),
        language: lang,
      );
    }

    // ---- Torch ----
    if (_containsAny(norm, [
      'torch on', 'flashlight on', 'torch jala', 'torch on karo',
      'ٹارچ آن',
    ])) {
      return CommandResult(
        action: CommandAction.torchOn,
        reply: t('Torch on.', 'Torch jala di.', 'ٹارچ آن کر دی۔'),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'torch off', 'flashlight off', 'torch band', 'torch off karo',
      'ٹارچ بند',
    ])) {
      return CommandResult(
        action: CommandAction.torchOff,
        reply: t('Torch off.', 'Torch band kar di.', 'ٹارچ بند کر دی۔'),
        language: lang,
      );
    }

    // ---- Volume (unmute first: "unmute" contains "mute") ----
    if (_containsAny(norm, [
      'volume up', 'volume zyada', 'volume badhao', 'awaz barhao',
      'awaz zyada', 'sound up', 'آواز بڑھاؤ',
    ])) {
      return CommandResult(
        action: CommandAction.volumeUp,
        reply: t('Volume up.', 'Volume barha di.', 'آواز بڑھا دی۔'),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'volume down', 'volume kam', 'volume ghatao', 'awaz kam',
      'sound down', 'آواز کم',
    ])) {
      return CommandResult(
        action: CommandAction.volumeDown,
        reply: t('Volume down.', 'Volume kam kar di.', 'آواز کم کر دی۔'),
        language: lang,
      );
    }
    if (_containsAny(norm, ['unmute', 'awaz kholo', 'sound on'])) {
      return CommandResult(
        action: CommandAction.volumeUnmute,
        reply: t('Unmuted.', 'Awaz khol di.', 'آواز کھول دی۔'),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'volume mute', 'mute karo', 'mute', 'awaz band', 'sound band',
      'آواز بند',
    ])) {
      return CommandResult(
        action: CommandAction.volumeMute,
        reply: t('Muted.', 'Awaz band kar di.', 'آواز بند کر دی۔'),
        language: lang,
      );
    }

    // ---- Coin toss & dice (pure chance, no API) ----
    if (_containsAny(norm, [
      'coin toss', 'sikka', 'heads or tails', 'toss karo', 'سکہ',
    ])) {
      final heads = _random.nextBool();
      return CommandResult(
        action: CommandAction.coinToss,
        reply: t(
          heads ? 'Heads.' : 'Tails.',
          heads ? 'Chit.' : 'Pat.',
          heads ? 'چت۔' : 'پٹ۔',
        ),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'dice', 'pansa', 'پانسہ', 'roll a dice', 'dice roll',
    ])) {
      final roll = _random.nextInt(6) + 1;
      return CommandResult(
        action: CommandAction.diceRoll,
        reply: t(
          'You rolled a $roll.',
          'Pansa $roll aaya.',
          'پانسہ $roll آیا۔',
        ),
        language: lang,
      );
    }

    // ---- Stopwatch ----
    if (norm.contains('stopwatch') || norm.contains('سٹاپ واچ')) {
      if (_containsAny(norm, ['start', 'shuru', 'chalu', 'شروع'])) {
        _stopwatchStart = time;
        return CommandResult(
          action: CommandAction.stopwatchStart,
          reply: t(
            'Stopwatch started.',
            'Stopwatch shuru kar di.',
            'سٹاپ واچ شروع کر دی۔',
          ),
          language: lang,
        );
      }
      if (_containsAny(norm, ['stop', 'band', 'ruk', 'بند'])) {
        if (_stopwatchStart == null) {
          return CommandResult(
            action: CommandAction.stopwatchStop,
            reply: t(
              'The stopwatch is not running.',
              'Stopwatch abhi chal nahi rahi.',
              'سٹاپ واچ ابھی چل نہیں رہی۔',
            ),
            language: lang,
          );
        }
        final elapsed = time.difference(_stopwatchStart!).inSeconds;
        _stopwatchStart = null;
        final pretty = _formatElapsed(elapsed, lang);
        return CommandResult(
          action: CommandAction.stopwatchStop,
          reply: t(
            'Stopwatch stopped: $pretty.',
            'Stopwatch band: $pretty.',
            'سٹاپ واچ بند: $pretty۔',
          ),
          language: lang,
        );
      }
    }

    // ---- Close Ayra itself (an app can only close itself) ----
    if ((_containsAny(norm, ['ayra', 'ایرا']) &&
            _containsAny(norm, ['band', 'close', 'minimize', 'بند'])) ||
        _containsAny(norm, ['app band', 'exit app', 'close app', 'minimize'])) {
      return CommandResult(
        action: CommandAction.closeApp,
        reply: t(
          'Closing Ayra. Allah Hafiz!',
          'Ayra band kar rahi hun. Allah Hafiz!',
          'ایرا بند کر رہی ہوں۔ اللہ حافظ!',
        ),
        language: lang,
      );
    }

    // ---- Windows-only desktop actions ----
    if (_containsAny(norm, [
      'organize desktop', 'organise desktop', 'desktop organize',
      'desktop saaf', 'desktop clean', 'ڈیسک ٹاپ ترتیب',
    ])) {
      return CommandResult(
        action: CommandAction.windowsOrganize,
        reply: t(
          'I can organise the Desktop, but only on Windows — and I will ask you to confirm first.',
          'Desktop organize kar sakti hun, lekin sirf Windows par — aur pehle tum se confirm karungi.',
          'ڈیسک ٹاپ ترتیب دے سکتی ہوں، لیکن صرف ونڈوز پر — اور پہلے آپ سے تصدیق کروں گی۔',
        ),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'empty recycle bin', 'recycle bin khali', 'recycle bin empty',
      'ری سائیکل بن خالی',
    ])) {
      return CommandResult(
        action: CommandAction.windowsRecycleBin,
        reply: t(
          'I can empty the Recycle Bin, but only on Windows — and I will ask you to confirm first.',
          'Recycle Bin khali kar sakti hun, lekin sirf Windows par — aur pehle tum se confirm karungi.',
          'ری سائیکل بن خالی کر سکتی ہوں، لیکن صرف ونڈوز پر — اور پہلے آپ سے تصدیق کروں گی۔',
        ),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'shutdown pc', 'shutdown computer', 'shutdown laptop', 'shut down pc',
      'pc band', 'computer band', 'pc shutdown', 'کمپیوٹر بند',
    ])) {
      return CommandResult(
        action: CommandAction.windowsShutdown,
        reply: t(
          'I can shut the PC down, but only on Windows — and I will ask you to confirm first.',
          'PC shutdown kar sakti hun, lekin sirf Windows par — aur pehle tum se confirm karungi.',
          'پی سی بند کر سکتی ہوں، لیکن صرف ونڈوز پر — اور پہلے آپ سے تصدیق کروں گی۔',
        ),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'lock pc', 'lock computer', 'lock laptop', 'pc lock', 'کمپیوٹر لاک',
    ])) {
      return CommandResult(
        action: CommandAction.windowsLock,
        reply: t(
          'I can lock the PC, but only on Windows.',
          'PC lock kar sakti hun, lekin sirf Windows par.',
          'پی سی لاک کر سکتی ہوں، لیکن صرف ونڈوز پر۔',
        ),
        language: lang,
      );
    }

    // ---- Dial / SMS ----
    final dialMatch =
        RegExp(r'(?:call|dial|phone)\s+(\+?[\d][\d\s\-]{5,})').firstMatch(norm);
    if (dialMatch != null) {
      final number = dialMatch.group(1)!.replaceAll(RegExp(r'[\s\-]'), '');
      return CommandResult(
        action: CommandAction.dial,
        data: 'tel:$number',
        reply: t('Calling $number…', '$number par call laga rahi hun…',
            '$number پر کال لگا رہی ہوں…'),
        language: lang,
      );
    }
    final smsMatch =
        RegExp(r'(?:sms|text|message)\s+(\+?[\d][\d\s\-]{5,})').firstMatch(norm);
    if (smsMatch != null) {
      final number = smsMatch.group(1)!.replaceAll(RegExp(r'[\s\-]'), '');
      return CommandResult(
        action: CommandAction.sms,
        data: 'sms:$number',
        reply: t('Opening messages for $number…',
            '$number ke liye messages khol rahi hun…',
            '$number کے لیے میسجز کھول رہی ہوں…'),
        language: lang,
      );
    }

    // ---- Search on a site ----
    final search = _parseSearch(norm, input);
    if (search != null) {
      return CommandResult(
        action: CommandAction.searchWeb,
        data: search.$1,
        reply: t(
          'Searching for "${search.$2}"…',
          '"${search.$2}" search kar rahi hun…',
          '"${search.$2}" تلاش کر رہی ہوں…',
        ),
        language: lang,
      );
    }

    // ---- Open a site / app ----
    final site = _matchSite(norm);
    if (site != null) {
      return CommandResult(
        action: CommandAction.openSite,
        data: site.$1,
        reply: t(
          'Opening ${site.$2}…',
          '${site.$2} khol rahi hun…',
          '${site.$2} کھول رہی ہوں…',
        ),
        language: lang,
      );
    }

    // ---- Open any installed app by name ("Chrome kholo") ----
    final appName = _parseOpenApp(norm, input);
    if (appName != null) {
      final lowerApp = appName.toLowerCase();
      if (lowerApp.contains('camera') || lowerApp.contains('کیمرہ')) {
        return CommandResult(
          action: CommandAction.openCamera,
          reply: t(
            'Opening camera…',
            'Camera khol rahi hun…',
            'کیمرہ کھول رہی ہوں…',
          ),
          language: lang,
        );
      }
      if (lowerApp.contains('wifi') || lowerApp.contains('wi-fi')) {
        return CommandResult(
          action: CommandAction.openSettings,
          data: 'wifi',
          reply: t(
            'Opening WiFi settings…',
            'WiFi settings khol rahi hun…',
            'وائی فائی سیٹنگز کھول رہی ہوں…',
          ),
          language: lang,
        );
      }
      if (lowerApp.contains('bluetooth')) {
        return CommandResult(
          action: CommandAction.openSettings,
          data: 'bluetooth',
          reply: t(
            'Opening Bluetooth settings…',
            'Bluetooth settings khol rahi hun…',
            'بلوٹوتھ سیٹنگز کھول رہی ہوں…',
          ),
          language: lang,
        );
      }
      if (lowerApp.contains('setting')) {
        return CommandResult(
          action: CommandAction.openSettings,
          data: 'settings',
          reply: t(
            'Opening settings…',
            'Settings khol rahi hun…',
            'سیٹنگز کھول رہی ہوں…',
          ),
          language: lang,
        );
      }
      return CommandResult(
        action: CommandAction.openApp,
        data: appName,
        reply: t(
          'Opening $appName…',
          '$appName khol rahi hun…',
          '$appName کھول رہی ہوں…',
        ),
        language: lang,
      );
    }

    // ---- Notes ----
    if (_containsAny(norm, ['show notes', 'show my notes', 'notes dikhao',
      'mere notes', 'my notes', 'نوٹ دکھاؤ', 'میرے نوٹ'])) {
      if (notes.isEmpty) {
        return CommandResult(
          action: CommandAction.noteList,
          reply: t('You have no notes yet. Say "note buy milk" to add one.',
              'Abhi koi note nahi hai. Note add karne ke liye bolo "note doodh lena hai".',
              'ابھی کوئی نوٹ نہیں ہے۔ نوٹ شامل کرنے کے لیے بولیں "نوٹ دودھ لینا ہے"۔'),
          language: lang,
        );
      }
      final lines = notes.asMap().entries.map((e) => '${e.key + 1}. ${e.value}');
      return CommandResult(
        action: CommandAction.noteList,
        reply: t('Your notes:\n${lines.join('\n')}',
            'Tumhare notes:\n${lines.join('\n')}',
            'آپ کے نوٹس:\n${lines.join('\n')}'),
        language: lang,
      );
    }
    if (_containsAny(norm, [
      'clear notes', 'delete notes', 'notes saaf', 'notes delete',
      'نوٹ صاف',
    ])) {
      notes.clear();
      return CommandResult(
        action: CommandAction.noteClear,
        reply: t('All notes cleared.', 'Saare notes saaf kar diye.',
            'تمام نوٹس صاف کر دیے۔'),
        language: lang,
      );
    }
    final noteText = _parseNote(input);
    if (noteText != null && noteText.isNotEmpty) {
      notes.add(noteText);
      return CommandResult(
        action: CommandAction.noteAdd,
        reply: t('Note saved: "$noteText".', 'Note save kar liya: "$noteText".',
            'نوٹ محفوظ کر لیا: "$noteText"۔'),
        language: lang,
      );
    }

    // ---- Remember / recall / forget ----
    final remembered = _tryRemember(norm, input, lang, t);
    if (remembered != null) return remembered;
    final recalled = _tryRecall(norm, input, lang, t);
    if (recalled != null) return recalled;
    if (_containsAny(norm, [
      'forget everything', 'sab bhool jao', 'sab kuch bhool', 'سب بھول جاؤ',
    ])) {
      memories.clear();
      return CommandResult(
        action: CommandAction.forget,
        reply: t('I forgot everything you asked me to remember.',
            'Jo kuch yaad rakhne ko kaha tha, sab bhool gayi.',
            'جو کچھ یاد رکھنے کو کہا تھا، سب بھول گئی۔'),
        language: lang,
      );
    }
    final forgot = _tryForget(norm, input, lang, t);
    if (forgot != null) return forgot;

    // ---- Jokes & quotes ----
    if (_containsAny(norm, ['joke', 'latifa', 'mazah', 'لطیفہ', 'مذاق'])) {
      final jokes = _jokes(lang);
      return CommandResult(
        action: CommandAction.joke,
        reply: jokes[_random.nextInt(jokes.length)],
        language: lang,
      );
    }
    if (_containsAny(norm, ['quote', 'aqwal', 'achhi baat', 'اقوال'])) {
      final quotes = _quotes(lang);
      return CommandResult(
        action: CommandAction.quote,
        reply: quotes[_random.nextInt(quotes.length)],
        language: lang,
      );
    }

    // ---- Fallback ----
    return CommandResult(
      action: CommandAction.unknown,
      reply: t(
        "I didn't understand that. Say 'help' to see what I can do.",
        "Samajh nahi aaya. 'help' bolo, main bataungi main kya kar sakti hun.",
        "سمجھ نہیں آیا۔ 'help' بولیں، میں بتاؤں گی میں کیا کر سکتی ہوں۔",
      ),
      language: lang,
    );
  }

  // ---------- helpers ----------

  final _random = Random.secure();

  /// When the stopwatch was started, if it is running.
  DateTime? _stopwatchStart;

  static String _detectLanguage(String input) {
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(input)) return 'ur';
    final lower = input.toLowerCase();
    const romanWords = [
      'kya', 'hai', 'hun', 'mera', 'meri', 'tum', 'mujhe', 'karo', 'kholo',
      'batao', 'bata', 'likho', 'yaad', 'rakho', 'lagao', 'dikhao', 'chahiye',
      'kaise', 'kab', 'kahan', 'bhai', 'acha', 'theek',
    ];
    for (final word in romanWords) {
      if (RegExp('\\b$word\\b').hasMatch(lower)) return 'roman';
    }
    return 'en';
  }

  static String _normalise(String lower) =>
      lower.replaceAll(RegExp(r'[؟?!.،,]+$'), '').trim();

  static bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }

  /// Whole-word match for Latin words ("date" must not fire inside
  /// "update", "time" must not fire inside "sometimes").
  static bool _hasWord(String text, String word) =>
      RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(text);

  static String _formatTime(DateTime time) {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  static String _formatDate(DateTime time) =>
      '${_weekdays[time.weekday - 1]}, ${time.day} ${_months[time.month - 1]} ${time.year}';

  static String _humanDuration(int seconds, String lang) {
    if (seconds < 60) {
      return lang == 'en'
          ? '$seconds second${seconds == 1 ? '' : 's'}'
          : '$seconds second';
    }
    if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return lang == 'en'
          ? '$minutes minute${minutes == 1 ? '' : 's'}'
          : '$minutes minute';
    }
    final hours = seconds ~/ 3600;
    return lang == 'en'
        ? '$hours hour${hours == 1 ? '' : 's'}'
        : '$hours ghanta';
  }

  /// Parses "set timer 5 minutes", "remind me in 10 minutes to call Ali",
  /// "5 minute ka timer", "10 منٹ کا ٹائمر". Returns (seconds, label).
  /// The label is captured from the original text so its case is kept.
  static (int, String)? _parseTimer(String norm, String original) {
    final match = RegExp(
      r'(\d+)\s*(seconds?|minutes?|hours?|sec|min|hr|second|minute|hour|منٹ|سیکنڈ|گھنٹہ|گھنٹے)',
    ).firstMatch(norm);
    if (match == null) return null;
    if (!norm.contains('timer') && !norm.contains('remind') &&
        !norm.contains('ٹائمر') && !norm.contains('yaad')) {
      return null;
    }
    final value = int.parse(match.group(1)!);
    final unit = match.group(2)!;
    final seconds = unit.startsWith('hour') || unit.startsWith('hr') ||
            unit.startsWith('گھنٹ')
        ? value * 3600
        : unit.startsWith('min') || unit.startsWith('منٹ')
            ? value * 60
            : value;
    var label = '';
    final toMatch = RegExp(r'\bto\s+(.+)$', caseSensitive: false)
            .firstMatch(original) ??
        RegExp(r'\bke\s+(.+)$', caseSensitive: false).firstMatch(original);
    if (toMatch != null) label = toMatch.group(1)!.trim();
    return (seconds, label);
  }

  /// Parses "set alarm 7 AM", "alarm 6:30 PM", "7 baje ka alarm lagao".
  /// Returns (hour 0-23, minute, label).
  static (int, int, String)? _parseAlarm(String norm) {
    if (!norm.contains('alarm') && !norm.contains('الارم')) return null;
    final match = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|baje|bajay)?',
    ).firstMatch(norm);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = match.group(2) == null ? 0 : int.parse(match.group(2)!);
    final suffix = match.group(3);
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return (hour, minute, '');
  }

  /// The app name after "open ..." / "... kholo".
  static String? _parseOpenApp(String norm, String original) {
    var match = RegExp(
      r'^(?:open|launch|start)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(original.trim());
    if (match != null) {
      final name = match.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }
    match = RegExp(
      r'^(.+?)\s+(?:kholo|khol|کھولو|کھول)\s*$',
      caseSensitive: false,
    ).firstMatch(original.trim());
    if (match != null) {
      final name = match.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  static String _formatElapsed(int seconds, String lang) {
    if (seconds < 60) {
      if (lang == 'ur') return '$seconds سیکنڈ';
      return '$seconds second${seconds == 1 ? '' : 's'}';
    }
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (lang == 'ur') {
      return rest == 0 ? '$minutes منٹ' : '$minutes منٹ $rest سیکنڈ';
    }
    final m = '$minutes minute${minutes == 1 ? '' : 's'}';
    return rest == 0 ? m : '$m $rest second${rest == 1 ? '' : 's'}';
  }

  /// Finds an arithmetic expression inside the text, if any.
  /// The match may start with an opening bracket or a sign, so
  /// "(2 + 3) * 4" is captured whole instead of "2 + 3) * 4".
  static String? _extractExpression(String norm) {
    final match =
        RegExp(r'[-+]?\(?\d[\d\s\.\+\-\*\/xX\%\(\)\^]*[\d\)]').firstMatch(norm);
    if (match == null) return null;
    final expr = match
        .group(0)!
        .replaceAll('x', '*')
        .replaceAll('X', '*')
        .trim();
    if (!RegExp(r'[\+\-\*\/\%\^]').hasMatch(expr)) return null;
    if (!RegExp(r'\d').hasMatch(expr)) return null;
    return expr;
  }

  CommandResult _calculate(String expr, String lang,
      String Function(String, String, String) t) {
    try {
      final value = Calculator.evaluate(expr);
      return CommandResult(
        action: CommandAction.calculate,
        reply: t(
          '$expr = ${Calculator.format(value)}',
          '$expr = ${Calculator.format(value)}',
          '$expr = ${Calculator.format(value)}',
        ),
        language: lang,
      );
    } on FormatException catch (e) {
      return CommandResult(
        action: CommandAction.calculate,
        reply: t(
          "I couldn't calculate that: ${e.message}.",
          'Hisaab nahi ho saka: ${e.message}.',
          'حساب نہیں ہو سکا: ${e.message}۔',
        ),
        language: lang,
      );
    }
  }

  static const _siteMap = <String, (String, String)>{
    'youtube': ('https://www.youtube.com', 'YouTube'),
    'یوٹیوب': ('https://www.youtube.com', 'YouTube'),
    'google': ('https://www.google.com', 'Google'),
    'گوگل': ('https://www.google.com', 'Google'),
    'github': ('https://github.com', 'GitHub'),
    'گٹ ہب': ('https://github.com', 'GitHub'),
    'whatsapp': ('https://web.whatsapp.com', 'WhatsApp'),
    'واٹس ایپ': ('https://web.whatsapp.com', 'WhatsApp'),
    'gmail': ('https://mail.google.com', 'Gmail'),
    'جی میل': ('https://mail.google.com', 'Gmail'),
    'maps': ('https://maps.google.com', 'Google Maps'),
    'google maps': ('https://maps.google.com', 'Google Maps'),
    'میپس': ('https://maps.google.com', 'Google Maps'),
    'spotify': ('https://open.spotify.com', 'Spotify'),
    'سپوٹیفائی': ('https://open.spotify.com', 'Spotify'),
    'facebook': ('https://www.facebook.com', 'Facebook'),
    'فیس بک': ('https://www.facebook.com', 'Facebook'),
    'instagram': ('https://www.instagram.com', 'Instagram'),
    'انسٹاگرام': ('https://www.instagram.com', 'Instagram'),
    'linkedin': ('https://www.linkedin.com', 'LinkedIn'),
    'لنکڈ ان': ('https://www.linkedin.com', 'LinkedIn'),
    'wikipedia': ('https://www.wikipedia.org', 'Wikipedia'),
    'ویکیپیڈیا': ('https://www.wikipedia.org', 'Wikipedia'),
    'twitter': ('https://x.com', 'X (Twitter)'),
    'ٹویٹر': ('https://x.com', 'X (Twitter)'),
    'stackoverflow': ('https://stackoverflow.com', 'Stack Overflow'),
    'chatgpt': ('https://chat.openai.com', 'ChatGPT'),
  };

  static (String, String)? _matchSite(String norm) {
    if (!_containsAny(norm, [
      'open', 'kholo', 'khol', 'launch', 'start', 'کھولو', 'کھول',
    ]) && !_siteMap.keys.any((key) => norm == key)) {
      return null;
    }
    for (final entry in _siteMap.entries) {
      if (norm.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// "search cats on youtube", "google par flutter search karo",
  /// "یوٹیوب پر بلی تلاش کرو". The query is captured from the original
  /// text so its case is kept.
  static (String, String)? _parseSearch(String norm, String original) {
    var match = RegExp(
      r'search(?:\s+for)?\s+(.+?)\s+on\s+(youtube|google)',
      caseSensitive: false,
    ).firstMatch(original);
    if (match != null) {
      final query = match.group(1)!.trim();
      final site = match.group(2)!.toLowerCase();
      final url = site == 'youtube'
          ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}'
          : 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';
      return (url, query);
    }
    match = RegExp(r'(youtube|google)\s+par\s+(.+?)\s+search',
            caseSensitive: false)
        .firstMatch(original);
    if (match != null) {
      final query = match.group(2)!.trim();
      final site = match.group(1)!.toLowerCase();
      final url = site == 'youtube'
          ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}'
          : 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';
      return (url, query);
    }
    match = RegExp(r'(?:search|google|یوٹیوب|گوگل)\s+(.+)$',
            caseSensitive: false)
        .firstMatch(original);
    if (match != null && norm.contains('search')) {
      final query = match.group(1)!.trim();
      if (query.isNotEmpty && !_siteMap.containsKey(query.toLowerCase())) {
        return (
          'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
          query,
        );
      }
    }
    return null;
  }

  /// Captures the note text from the original input so its case is kept.
  static String? _parseNote(String original) {
    final match = RegExp(
      r'^(?:note|not|نوٹ)\s*(?::|likho|likh do|likh|لکھو)?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(original.trim());
    if (match == null) return null;
    final text = match.group(1)!.trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'likho' || text.toLowerCase() == 'likh do') {
      return null;
    }
    return text;
  }

  static String _cleanKey(String key) {
    var cleaned = key.toLowerCase().trim();
    for (final prefix in ['my ', 'mera ', 'meri ', 'mine ', 'اپنا ', 'میرا ', 'میری ']) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }
    return cleaned;
  }

  CommandResult? _tryRemember(String norm, String original, String lang,
      String Function(String, String, String) t) {
    // English: "remember my name is Muzammil" / "remember that X is Y".
    // Matched on the original text so the value keeps its case.
    var match = RegExp(r'remember(?:\s+that)?\s+(.+?)\s+is\s+(.+)$',
            caseSensitive: false)
        .firstMatch(original);
    if (match != null) {
      final key = _cleanKey(match.group(1)!);
      final value = match.group(2)!.trim();
      if (key.isEmpty || value.isEmpty) return null;
      memories[key] = value;
      return _rememberedReply(key, value, lang, t);
    }
    // Roman Urdu: "yaad rakho mera naam Muzammil hai" — last word is the
    // value, the rest is the key.
    match = RegExp(r'yaad rakho\s+(.+)\s+hai\s*$', caseSensitive: false)
        .firstMatch(original);
    if (match != null) {
      final remembered = _rememberKeyValue(match.group(1)!, lang, t);
      if (remembered != null) return remembered;
    }
    // Urdu script: "یاد رکھو میرا نام مزمل ہے".
    match = RegExp(r'یاد رکھو\s+(.+)\s+ہے\s*$').firstMatch(original);
    if (match != null) {
      final remembered = _rememberKeyValue(match.group(1)!, lang, t);
      if (remembered != null) return remembered;
    }
    return null;
  }

  /// Splits "mera naam Muzammil" into key "naam" and value "Muzammil".
  CommandResult? _rememberKeyValue(String phrase, String lang,
      String Function(String, String, String) t) {
    final parts = phrase.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final value = parts.removeLast();
    final key = _cleanKey(parts.join(' '));
    if (key.isEmpty || value.isEmpty) return null;
    memories[key] = value;
    return _rememberedReply(key, value, lang, t);
  }

  CommandResult _rememberedReply(String key, String value, String lang,
      String Function(String, String, String) t) {
    return CommandResult(
      action: CommandAction.remember,
      reply: t(
        'Got it — I will remember that your $key is $value.',
        'Theek hai — yaad rakh liya ke tumhara $key $value hai.',
        'ٹھیک ہے — یاد رکھ لیا کہ آپ کا $key $value ہے۔',
      ),
      language: lang,
    );
  }

  CommandResult? _tryRecall(String norm, String original, String lang,
      String Function(String, String, String) t) {
    final match = RegExp(
      r"(?:what(?: is|'s)?\s+my\s+(.+?)\??|mera\s+(.+?)\s+kya\s+hai|میرا\s+(.+?)\s+کیا\s+ہے)",
      caseSensitive: false,
    ).firstMatch(original);
    if (match == null) return null;
    final rawKey = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    final key = _cleanKey(rawKey);
    final value = memories[key] ??
        memories.entries
            .firstWhere(
              (e) => e.key.contains(key) || key.contains(e.key),
              orElse: () => const MapEntry('', ''),
            )
            .value;
    if (value.isEmpty) {
      return CommandResult(
        action: CommandAction.recall,
        reply: t(
          "I don't know your $key yet. Say 'remember my $key is …' to teach me.",
          'Mujhe tumhara $key abhi nahi pata. Sikhao: "yaad rakho mera $key … hai".',
          'مجھے آپ کا $key ابھی نہیں پتا۔ سکھائیں: "یاد رکھو میرا $key … ہے"۔',
        ),
        language: lang,
      );
    }
    return CommandResult(
      action: CommandAction.recall,
      reply: t(
        'Your $key is $value.',
        'Tumhara $key $value hai.',
        'آپ کا $key $value ہے۔',
      ),
      language: lang,
    );
  }

  CommandResult? _tryForget(String norm, String original, String lang,
      String Function(String, String, String) t) {
    final match = RegExp(
      r'forget\s+(?:my\s+)?(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(original);
    if (match == null) {
      final m2 = RegExp(r'(.+?)\s+bhool\s+jao', caseSensitive: false)
          .firstMatch(original);
      if (m2 == null) return null;
      final key = _cleanKey(m2.group(1)!);
      if (!memories.containsKey(key)) return null;
      memories.remove(key);
      return _forgotReply(key, lang, t);
    }
    final key = _cleanKey(match.group(1)!);
    if (!memories.containsKey(key)) return null;
    memories.remove(key);
    return _forgotReply(key, lang, t);
  }

  CommandResult _forgotReply(String key, String lang,
      String Function(String, String, String) t) {
    return CommandResult(
      action: CommandAction.forget,
      reply: t(
        'Okay — I forgot your $key.',
        'Theek hai — tumhara $key bhool gayi.',
        'ٹھیک ہے — آپ کا $key بھول گئی۔',
      ),
      language: lang,
    );
  }

  static CommandResult? _tryConvert(String norm, String lang,
      String Function(String, String, String) t) {
    final match = RegExp(
      r'convert\s+(\d+(?:\.\d+)?)\s*([a-z°]+)\s*(?:to|in|mein)?\s*([a-z°]+)',
    ).firstMatch(norm);
    if (match == null) return null;
    final value = double.parse(match.group(1)!);
    final from = _unit(match.group(2)!);
    final to = _unit(match.group(3)!);
    if (from == null || to == null || from.$1 != to.$1) return null;
    double result;
    if (from.$1 == 'temp') {
      result = _convertTemp(value, from.$2, to.$2);
    } else {
      result = value * from.$2 / to.$2;
    }
    final pretty = Calculator.format(result);
    return CommandResult(
      action: CommandAction.convert,
      reply: t(
        '$value ${from.$3} = $pretty ${to.$3}.',
        '$value ${from.$3} = $pretty ${to.$3}.',
        '$value ${from.$3} = $pretty ${to.$3}۔',
      ),
      language: lang,
    );
  }

  /// (category, factor-to-base, display name)
  static (String, double, String)? _unit(String raw) {
    switch (raw) {
      case 'km':
      case 'kilometer':
      case 'kilometers':
        return ('length', 1000, 'km');
      case 'mi':
      case 'mile':
      case 'miles':
        return ('length', 1609.34, 'miles');
      case 'm':
      case 'meter':
      case 'meters':
        return ('length', 1, 'm');
      case 'ft':
      case 'feet':
      case 'foot':
        return ('length', 0.3048, 'ft');
      case 'cm':
      case 'centimeter':
      case 'centimeters':
        return ('length', 0.01, 'cm');
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        return ('weight', 1, 'kg');
      case 'lb':
      case 'lbs':
      case 'pound':
      case 'pounds':
        return ('weight', 0.453592, 'lb');
      case 'l':
      case 'liter':
      case 'liters':
        return ('volume', 1, 'L');
      case 'ml':
      case 'milliliter':
      case 'milliliters':
        return ('volume', 0.001, 'ml');
      case 'c':
      case 'celsius':
      case '°c':
        return ('temp', 0, '°C');
      case 'f':
      case 'fahrenheit':
      case '°f':
        return ('temp', 1, '°F');
    }
    return null;
  }

  static double _convertTemp(double value, double from, double to) {
    if (from == to) return value;
    if (from == 0) return value * 9 / 5 + 32; // C -> F
    return (value - 32) * 5 / 9; // F -> C
  }

  String _generatePassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#\$%^&*';
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  static List<String> _jokes(String lang) {
    if (lang == 'ur') {
      return [
        'پروگرامر اندھیرا کیوں پسند کرتا ہے؟ کیونکہ روشنی میں بگز آ جاتے ہیں۔',
        'میرا کمپیوٹر اتنا سست ہے کہ اس نے مجھے صبر سکھا دیا۔',
        'وائی فائی نے کہا: تمہارا کنکشن کمزور ہے۔ میں نے کہا: میرا نہیں، تمہارا راؤٹر کمزور ہے۔',
      ];
    }
    if (lang == 'roman') {
      return [
        'Programmer andhera kyun pasand karta hai? Kyunki roshni mein bugs aa jate hain.',
        'Mera computer itna slow hai ke us ne mujhe sabar sikha diya.',
        'WiFi ne kaha: tumhara connection weak hai. Maine kaha: mera nahi, tumhara router weak hai.',
      ];
    }
    return [
      'Why do programmers prefer dark mode? Because light attracts bugs.',
      'I told my computer I needed a break, and now it keeps sending me KitKat ads.',
      'Why did the developer go broke? Because he used up all his cache.',
    ];
  }

  static List<String> _quotes(String lang) {
    if (lang == 'ur') {
      return [
        'چھوٹے قدم روز، بڑا فرق بناتے ہیں۔',
        'محنت کبھی ضائع نہیں ہوتی۔',
        'آج کا کام کل پر مت چھوڑو۔',
      ];
    }
    if (lang == 'roman') {
      return [
        'Chhote kadam roz, bara farq banate hain.',
        'Mehnat kabhi zaya nahi hoti.',
        'Aaj ka kaam kal par mat chhoro.',
      ];
    }
    return [
      'The best time to plant a tree was twenty years ago. The second best time is now.',
      'Small steps every day add up to big change.',
      'Discipline is choosing what you want most over what you want now.',
    ];
  }
}

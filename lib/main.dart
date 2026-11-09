import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_engine.dart';
import 'memory_store.dart';
import 'services/device_service.dart';
import 'services/voice_service.dart';
import 'widgets/globe_3d.dart';
import 'widgets/orb_3d.dart';
import 'widgets/tilt_card.dart';

void main() {
  runApp(const AyraApp());
}

/// Ayra — a free, on-device voice assistant.
/// No paid API, no account, no cloud. Speech recognition and speech
/// synthesis use the device itself; commands are answered by a local
/// rule engine. Premium look comes from clean spacing, type and glass
/// cards — never from 3D gimmicks.
class AyraApp extends StatelessWidget {
  const AyraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A0E27);
    const panel = Color(0xFF141A3A);
    const electricBlue = Color(0xFF3B82F6);
    const purple = Color(0xFF8B5CF6);
    return MaterialApp(
      title: 'Ayra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: const ColorScheme.dark(
          primary: electricBlue,
          secondary: purple,
          surface: panel,
        ),
        cardTheme: CardThemeData(
          color: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1E2547),
          labelStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E2547),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class _Exchange {
  _Exchange(this.userText, this.reply);
  final String userText;
  final String reply;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _engine = CommandEngine();
  final _store = MemoryStore();
  final _voice = VoiceService();
  final _device = DeviceService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  bool _listening = false;
  bool _speakReplies = true;
  bool _listenUrdu = false;
  String _heard = '';
  String _reply =
      'Salam! Main Ayra hun. Tap the orb and speak, or type below.';
  final List<_Exchange> _history = [];
  Timer? _timer;
  String _timerLabel = '';
  bool _closeAfterReply = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _store.load();
    setState(() {
      _engine.notes.addAll(saved.notes);
      _engine.memories.addAll(saved.memories);
    });
  }

  Future<void> _save() async {
    await _store.save(_engine.notes, _engine.memories);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voice.stopListening();
      setState(() {
        _listening = false;
      });
      return;
    }
    final ok = await _voice.initialize();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is needed to listen.'),
        ),
      );
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await _voice.startListening(
      localeId: _listenUrdu ? 'ur-PK' : 'en-US',
      onResult: (text) {
        setState(() => _heard = text);
      },
      onFinal: (text) async {
        setState(() {
          _listening = false;
        });
        if (text.trim().isNotEmpty) {
          await _runCommand(text.trim());
        }
      },
    );
  }

  Future<void> _runCommand(String text) async {
    final result = _engine.handle(text);
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
        final ok = await _device.openAppByName(result.data ?? '');
        if (!ok) reply = 'Could not find or open that app on this device.';
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
        _closeAfterReply = true;
        break;
      case CommandAction.windowsOrganize:
      case CommandAction.windowsRecycleBin:
      case CommandAction.windowsShutdown:
      case CommandAction.windowsLock:
        reply = await _handleWindowsAction(result);
        break;
      case CommandAction.timerSet:
        _startTimer(result);
        break;
      case CommandAction.noteAdd:
      case CommandAction.noteClear:
      case CommandAction.remember:
      case CommandAction.forget:
        await _save();
        break;
      default:
        break;
    }

    if (!mounted) return;
    setState(() {
      _reply = reply;
      _history.insert(0, _Exchange(text, reply));
      if (_history.length > 30) _history.removeLast();
    });
    if (_speakReplies) {
      await _voice.speak(reply, result.language);
    }
    if (_closeAfterReply) {
      _closeAfterReply = false;
      SystemNavigator.pop();
    }
  }

  Future<String> _handleWindowsAction(CommandResult result) async {
    if (!_device.isWindows) {
      return 'This only works in the Windows app — on this device it is not available.';
    }
    final actionName = switch (result.action) {
      CommandAction.windowsOrganize => 'organise the Desktop',
      CommandAction.windowsRecycleBin => 'empty the Recycle Bin',
      CommandAction.windowsShutdown => 'shut down the PC',
      CommandAction.windowsLock => 'lock the PC',
      _ => 'do this',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Text('Are you sure you want to $actionName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, do it'),
          ),
        ],
      ),
    );
    if (confirmed != true) return 'Okay — cancelled. Nothing was changed.';
    return switch (result.action) {
      CommandAction.windowsOrganize => await _device.organizeDesktop(),
      CommandAction.windowsRecycleBin => await _device.emptyRecycleBin(),
      CommandAction.windowsShutdown => await _device.shutdownPc(),
      CommandAction.windowsLock => await _device.lockPc(),
      _ => 'Done.',
    };
  }

  void _startTimer(CommandResult result) {
    final parts = (result.data ?? '').split('|');
    final seconds = int.tryParse(parts.first) ?? 0;
    final label = parts.length > 1 ? parts[1] : 'Timer';
    _timer?.cancel();
    _timerLabel = label;
    _timer = Timer(Duration(seconds: seconds), () async {
      if (!mounted) return;
      final message = 'Timer done${label == 'Timer' ? '' : ': $label'}.';
      setState(() {
        _reply = message;
        _history.insert(0, _Exchange('⏰ $label', message));
      });
      await _voice.speak(message, 'en');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    });
  }

  void _quick(String text) {
    _inputController.clear();
    _runCommand(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AYRA',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            Text(
              'Free voice assistant • No API • On-device',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _speakReplies ? 'Mute replies' : 'Speak replies',
            icon: Icon(
              _speakReplies ? Icons.volume_up : Icons.volume_off,
            ),
            onPressed: () async {
              setState(() => _speakReplies = !_speakReplies);
              if (!_speakReplies) await _voice.stopSpeaking();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(),
              const SizedBox(height: 8),
              _buildLanguageToggle(),
              const SizedBox(height: 16),
              TiltCard(child: _buildReplyCard()),
              const SizedBox(height: 16),
              _buildQuickChips(),
              const SizedBox(height: 16),
              _buildInputRow(),
              if (_engine.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                TiltCard(child: _buildNotesCard()),
              ],
              if (_engine.memories.isNotEmpty) ...[
                const SizedBox(height: 16),
                TiltCard(child: _buildMemoryCard()),
              ],
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 16),
                TiltCard(child: _buildHistoryCard()),
              ],
              const SizedBox(height: 20),
              const Text(
                'Honest limits: Ayra cannot unlock a phone, send WhatsApp messages by itself, or run with the app closed. Free-form AI chat needs a cloud key later — today it works with on-device voice and rules only.',
                style: TextStyle(fontSize: 11, color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The 3D hero: a rotating particle globe with the ringed voice orb
  /// floating in front of it. Drag the orb to tilt it in 3D.
  Widget _buildHero() {
    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Globe3D(size: 260),
          Orb3D(
            listening: _listening,
            onTap: _toggleListening,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('English'),
          selected: !_listenUrdu,
          onSelected: (_) => setState(() => _listenUrdu = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('اردو'),
          selected: _listenUrdu,
          onSelected: (_) => setState(() => _listenUrdu = true),
        ),
      ],
    );
  }

  Widget _buildReplyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Ayra',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                if (_timer != null && _timer!.isActive)
                  Chip(
                    avatar: const Icon(Icons.timer, size: 16),
                    label: Text('Timer: $_timerLabel'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_heard.isNotEmpty)
              Text(
                'You: $_heard',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            if (_heard.isNotEmpty) const SizedBox(height: 6),
            SelectableText(
              _reply,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChips() {
    const actions = [
      ('YouTube', 'open YouTube', Icons.play_circle_fill),
      ('Google', 'open Google', Icons.search),
      ('Time', 'what time is it', Icons.access_time),
      ('Joke', 'tell me a joke', Icons.emoji_emotions),
      ('Notes', 'show my notes', Icons.note_alt),
      ('Battery', 'battery', Icons.battery_std),
      ('Camera', 'open camera', Icons.camera_alt),
      ('Alarm', 'set alarm 7 AM', Icons.alarm),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, command, icon) in actions)
          ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: () => _quick(command),
          ),
      ],
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(
              hintText: 'Type a command… e.g. calculate 15 * 4',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
            ),
            onSubmitted: (text) {
              if (text.trim().isEmpty) return;
              _inputController.clear();
              _runCommand(text.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            final text = _inputController.text.trim();
            if (text.isEmpty) return;
            _inputController.clear();
            _runCommand(text);
          },
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.send),
        ),
      ],
    );
  }

  Widget _buildNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notes',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _engine.notes.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('• ${_engine.notes[i]}')),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        setState(() => _engine.notes.removeAt(i));
                        await _save();
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Remembered',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final entry in _engine.memories.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('• ${entry.key}: ${entry.value}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final item in _history.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You: ${item.userText}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(item.reply),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

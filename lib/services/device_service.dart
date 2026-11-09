import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

/// The bridge between Ayra's rule engine and the real device.
/// Every method is honest about what it can and cannot do:
/// - Opening links, dialling and SMS work on Android and Windows.
/// - Torch and battery work on Android (battery also on Windows).
/// - Opening installed apps by name, camera, alarms and settings work
///   on Android only (intents + package list, no API, no account).
/// - Volume works wherever the device reports it.
/// - Desktop organisation, Recycle Bin, lock and shutdown are Windows-only
///   and always need the user's confirmation in the UI first.
/// - Nothing here can unlock a phone, send a WhatsApp message by itself,
///   close another app, or run while the app is closed.
class DeviceService {
  final Battery _battery = Battery();

  /// Opens a URL in the browser or the matching app.
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Battery level as a percentage (0-100), or -1 when unavailable.
  Future<int> batteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return -1;
    }
  }

  /// Turns the torch on. Returns false on devices without a flashlight
  /// (for example a Windows PC).
  Future<bool> torchOn() async {
    try {
      await TorchLight.enableTorch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> torchOff() async {
    try {
      await TorchLight.disableTorch();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get isWindows => Platform.isWindows;

  static const _appsChannel = MethodChannel('ayra/apps');

  /// Opens an installed app by its spoken name ("Chrome kholo").
  /// Android only. The native side (MainActivity) asks Android's own
  /// PackageManager — no plugin, no API. Returns false when not found.
  Future<bool> openAppByName(String query) async {
    if (!Platform.isAndroid) return false;
    final q = query.trim().toLowerCase();
    if (q.length < 3 || q == 'app') return false;
    try {
      final result = await _appsChannel.invokeMethod<bool>(
        'openAppByName',
        {'query': q},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the camera app. Android only.
  Future<bool> openCamera() async {
    if (!Platform.isAndroid) return false;
    try {
      const intent =
          AndroidIntent(action: 'android.media.action.IMAGE_CAPTURE');
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sets an alarm in the system clock app. Android only.
  Future<bool> setAlarm(int hour, int minute, String label) async {
    if (!Platform.isAndroid) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.HOUR': hour,
          'android.intent.extra.alarm.MINUTES': minute,
          'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': false,
        },
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens WiFi, Bluetooth or general settings. Android only.
  Future<bool> openSettings(String which) async {
    if (!Platform.isAndroid) return false;
    final action = switch (which) {
      'wifi' => 'android.settings.WIFI_SETTINGS',
      'bluetooth' => 'android.settings.BLUETOOTH_SETTINGS',
      _ => 'android.settings.SETTINGS',
    };
    try {
      final intent = AndroidIntent(action: action);
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Media volume up by one step. Returns false when unavailable.
  Future<bool> volumeUp() async {
    try {
      final current = await VolumeController.instance.getVolume();
      await VolumeController.instance.setVolume((current + 0.1).clamp(0.0, 1.0));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Media volume down by one step. Returns false when unavailable.
  Future<bool> volumeDown() async {
    try {
      final current = await VolumeController.instance.getVolume();
      await VolumeController.instance.setVolume((current - 0.1).clamp(0.0, 1.0));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mutes the media volume. Returns false when unavailable.
  Future<bool> volumeMute() async {
    try {
      await VolumeController.instance.setMute(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unmutes the media volume. Returns false when unavailable.
  Future<bool> volumeUnmute() async {
    try {
      await VolumeController.instance.setMute(false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Moves loose files on the Windows Desktop into folders by type
  /// (Images, Documents, Videos, Music, Archives, Apps, Other).
  /// Windows only. Returns a short summary of what moved.
  Future<String> organizeDesktop() async {
    if (!Platform.isWindows) {
      return 'Desktop organisation only works on Windows.';
    }
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return 'Could not find the Windows home folder.';
    final desktop = Directory('$home\\Desktop');
    if (!await desktop.exists()) return 'Desktop folder not found.';
    const groups = {
      'Images': {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'},
      'Documents': {'.pdf', '.docx', '.doc', '.txt', '.xlsx', '.pptx'},
      'Videos': {'.mp4', '.mkv', '.mov', '.avi'},
      'Music': {'.mp3', '.wav', '.flac'},
      'Archives': {'.zip', '.rar', '.7z'},
      'Apps': {'.exe', '.msi'},
    };
    var moved = 0;
    var skipped = 0;
    await for (final entity in desktop.list()) {
      if (entity is! File) {
        skipped++;
        continue;
      }
      final name = entity.path.split('\\').last;
      final dot = name.lastIndexOf('.');
      final ext = dot == -1 ? '' : name.substring(dot).toLowerCase();
      var group = 'Other';
      for (final entry in groups.entries) {
        if (entry.value.contains(ext)) group = entry.key;
      }
      final targetDir = Directory('${desktop.path}\\$group');
      await targetDir.create(recursive: true);
      try {
        await entity.rename('${targetDir.path}\\$name');
        moved++;
      } catch (_) {
        skipped++;
      }
    }
    return 'Desktop organised: $moved file(s) moved into folders'
        '${skipped > 0 ? ', $skipped skipped' : ''}.';
  }

  /// Empties the Windows Recycle Bin. Windows only.
  Future<String> emptyRecycleBin() async {
    if (!Platform.isWindows) {
      return 'Emptying the Recycle Bin only works on Windows.';
    }
    final result = await Process.run(
      'powershell',
      ['-Command', 'Clear-RecycleBin -Force'],
      runInShell: true,
    );
    if (result.exitCode == 0) return 'Recycle Bin emptied.';
    return 'Could not empty the Recycle Bin (${result.stderr}).';
  }

  /// Shuts the PC down in 30 seconds (enough time to cancel).
  /// Windows only.
  Future<String> shutdownPc() async {
    if (!Platform.isWindows) {
      return 'Shutdown only works on Windows.';
    }
    await Process.run('shutdown', ['/s', '/t', '30'], runInShell: true);
    return 'PC will shut down in 30 seconds. Run "shutdown /a" to cancel.';
  }

  /// Locks the PC. Windows only.
  Future<String> lockPc() async {
    if (!Platform.isWindows) {
      return 'Locking only works on Windows.';
    }
    await Process.run(
      'rundll32.exe',
      ['user32.dll,LockWorkStation'],
      runInShell: true,
    );
    return 'PC locked.';
  }
}

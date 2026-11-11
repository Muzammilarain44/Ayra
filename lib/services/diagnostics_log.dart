import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Small rotating debug log for the background trigger loop.
///
/// The background isolate used to fail silently — no logging, no
/// notification state, nothing visible from the device. This file is
/// the paper trail: every loop state change, error and heard
/// transcript is appended here (with a timestamp) so the next phone
/// test can be diagnosed from the device instead of from a user
/// report. The UI's "Diagnostics share karo" button copies this file.
///
/// Never throws: every operation is guarded, because logging must
/// never break the loop it is watching. The file is capped (last
/// 200 lines) so it cannot grow without bound.
class DiagnosticsLog {
  static const _fileName = 'ayra-diagnostics.log';

  /// Lines kept after a rotation.
  static const maxLines = 200;

  /// Rewrite (trim) once the file grows past this many lines.
  static const _trimAboveLines = 300;

  static Future<File?> _logFile() async {
    try {
      // No caching: the documents directory is looked up fresh each
      // time (it is the same in production, and tests re-point the
      // mock at a new temp dir per test).
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  /// Appends one timestamped line. Never throws.
  static Future<void> append(String line) async {
    try {
      final file = await _logFile();
      if (file == null) return;
      final now = DateTime.now();
      final stamp =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      await file.writeAsString(
        '[$stamp] $line\n',
        mode: FileMode.append,
        flush: true,
      );
      await _trimIfNeeded(file);
    } catch (e) {
      // Logging must never break the loop — keep the failure in
      // debug output only.
      debugPrint('Ayra diagnostics log failed: $e');
    }
  }

  /// The last [maxLines] lines of the log, newest last. Empty when
  /// there is no log yet. Never throws.
  static Future<String> readTail({int maxLines = 100}) async {
    try {
      final file = await _logFile();
      if (file == null || !await file.exists()) return '';
      final lines = await file.readAsLines();
      final tail = lines.length <= maxLines
          ? lines
          : lines.sublist(lines.length - maxLines);
      return tail.join('\n');
    } catch (_) {
      return '';
    }
  }

  /// Deletes the log. Never throws.
  static Future<void> clear() async {
    try {
      final file = await _logFile();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _trimIfNeeded(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.length <= _trimAboveLines) return;
      final kept = lines.sublist(lines.length - maxLines);
      await file.writeAsString('${kept.join('\n')}\n', flush: true);
    } catch (_) {
      // Trimming is best-effort only.
    }
  }
}

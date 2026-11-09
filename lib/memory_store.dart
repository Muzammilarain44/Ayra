import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists Ayra's notes and remembered facts on the device only.
/// Nothing is sent anywhere. Storage keys are fixed so a future version
/// of the app can read the same data.
class MemoryStore {
  static const _notesKey = 'ayra_notes';
  static const _memoriesKey = 'ayra_memories';

  Future<({List<String> notes, Map<String, String> memories})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final notes = prefs.getStringList(_notesKey) ?? <String>[];
    final raw = prefs.getString(_memoriesKey);
    final memories = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        memories[entry.key] = entry.value.toString();
      }
    }
    return (notes: notes, memories: memories);
  }

  Future<void> save(List<String> notes, Map<String, String> memories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_notesKey, notes);
    await prefs.setString(_memoriesKey, jsonEncode(memories));
  }
}

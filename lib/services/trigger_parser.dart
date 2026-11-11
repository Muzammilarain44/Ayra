/// Trigger-phrase parsing for Ayra's background listening.
///
/// When the assistant is ON, every recognised sentence is checked for the
/// trigger phrase ("Hello Ayra"). Only the words AFTER the trigger are a
/// command; anything without the trigger is ignored.
///
/// This file is pure Dart (no plugins) so it is unit-testable.
library;

/// The trigger phrase and the mishearings the on-device recogniser
/// commonly produces for "Hello" ("Hallo", "Halo", "Helo") and "Ayra"
/// ("Aira", "Ira", "Era", "Ara", "Ayrah", "Aera", "Ayraa", "Eraa"),
/// plus the natural "Hey" variant. Roman Urdu has no speech locale,
/// so the recogniser hears English approximations of the name — all
/// of them count as the trigger. Matching is case-insensitive and
/// ignores commas.
const List<String> triggerPhrases = [
  'hello ayra',
  'hey ayra',
  'hallo ayra',
  'halo ayra',
  'helo ayra',
  'hello aira',
  'hey aira',
  'hallo aira',
  'halo aira',
  'helo aira',
  'hello ira',
  'hey ira',
  'hallo ira',
  'halo ira',
  'helo ira',
  'hello era',
  'hey era',
  'hallo era',
  'halo era',
  'helo era',
  'hello ara',
  'hey ara',
  'hallo ara',
  'halo ara',
  'helo ara',
  'hello ayrah',
  'hey ayrah',
  'hallo ayrah',
  'halo ayrah',
  'helo ayrah',
  'hello aera',
  'hey aera',
  'hallo aera',
  'halo aera',
  'helo aera',
  'hello ayraa',
  'hey ayraa',
  'hallo ayraa',
  'halo ayraa',
  'helo ayraa',
  'hello eraa',
  'hey eraa',
  'hallo eraa',
  'halo eraa',
  'helo eraa',
];

/// Finds the trigger in [transcript] and returns the command after it.
///
/// Returns `null` when the transcript has no trigger (ignore it).
/// Returns `''` when the transcript is only the trigger ("Hello Ayra"
/// with nothing after it) — the caller may answer and wait for the
/// next sentence as the command.
String? extractCommandAfterTrigger(String transcript) {
  final normalised = transcript
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalised.isEmpty) return null;
  // Longest first: 'hey ayra' is a prefix of 'hey ayrah', so the
  // shorter trigger must not win and leave a stray 'h' behind.
  final ordered = triggerPhrases.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final trigger in ordered) {
    final index = normalised.indexOf(trigger);
    if (index != -1) {
      return normalised.substring(index + trigger.length).trim();
    }
  }
  // Looser match: the greeting and the name need not be adjacent —
  // the recogniser sometimes splits them across words ("hello my
  // ayra", "hello there ayra"). One or two words may sit between
  // them; anything after the name is the command.
  final loose = RegExp(
    r'\b(?:hello|hey|hallo|halo|helo)\b(?:\s+\w+){0,2}?\s+'
    r'(aera|ayraa|eraa|ayra|aira|ira|era|ara|ayrah)\b',
  ).firstMatch(normalised);
  if (loose != null) {
    return normalised.substring(loose.end).trim();
  }
  return null;
}

/// True when the transcript is only the trigger phrase, nothing after it.
bool isTriggerOnly(String transcript) =>
    extractCommandAfterTrigger(transcript) == '';

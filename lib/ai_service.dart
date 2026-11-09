/// Placeholder for a future cloud AI connection.
///
/// Ayra today works fully offline with on-device speech and a rule engine —
/// no API key, no account, no cost. When Muzammil can afford a cloud key,
/// this is the single place to wire it in (for example a free Gemini key
/// through a Supabase Edge Function). Nothing in the app calls this class
/// yet; it exists so the upgrade is one file, not a rewrite.
class AiService {
  /// True only after a key has been configured by the user.
  bool get isConfigured => false;

  /// Free-form chat. Refuses honestly until a cloud key is configured.
  Future<String> ask(String prompt) async {
    return 'Cloud AI is not set up yet. Ayra works without it — ask me to '
        'open something, calculate, remember things, or set a timer. '
        'When you have a free API key, we can switch this on.';
  }
}

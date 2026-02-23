import 'package:shared_preferences/shared_preferences.dart';

class RecentContactsRepository {
  const RecentContactsRepository();

  static const _recentRecipientsKey = 'contacts.recent_recipients';
  static const int _maxRecipients = 5;

  Future<List<String>> loadRecentRecipients() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        prefs.getStringList(_recentRecipientsKey) ?? const <String>[];
    return _normalize(stored);
  }

  Future<List<String>> rememberRecipient(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!_looksLikeEmail(normalizedEmail)) {
      return loadRecentRecipients();
    }

    final current = await loadRecentRecipients();
    final updated = <String>[
      normalizedEmail,
      ...current.where((item) => item != normalizedEmail)
    ];
    final trimmed = updated.take(_maxRecipients).toList(growable: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentRecipientsKey, trimmed);
    return trimmed;
  }

  List<String> _normalize(List<String> source) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in source) {
      final value = raw.trim().toLowerCase();
      if (!_looksLikeEmail(value) || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      result.add(value);
      if (result.length >= _maxRecipients) {
        break;
      }
    }
    return result;
  }

  bool _looksLikeEmail(String value) {
    if (value.isEmpty || value.length < 5) {
      return false;
    }
    final at = value.indexOf('@');
    if (at <= 0 || at == value.length - 1) {
      return false;
    }
    return value.substring(at + 1).contains('.');
  }
}

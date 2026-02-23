class YandexUser {
  const YandexUser({
    required this.id,
    required this.login,
    required this.defaultEmail,
    required this.emails,
  });

  final String id;
  final String login;
  final String? defaultEmail;
  final List<String> emails;

  String? get bestEmail {
    final normalizedDefault = defaultEmail?.trim();
    if (normalizedDefault != null && normalizedDefault.isNotEmpty) {
      return normalizedDefault;
    }
    for (final email in emails) {
      final normalized = email.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  String get identifier {
    final email = bestEmail;
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final normalizedLogin = login.trim();
    if (normalizedLogin.isNotEmpty) {
      return normalizedLogin;
    }
    return id.trim();
  }

  factory YandexUser.fromJson(Map<String, dynamic> json) {
    final rawEmails = json['emails'];
    final emails = <String>[];
    if (rawEmails is List) {
      for (final item in rawEmails) {
        final value = item?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          emails.add(value);
        }
      }
    }

    final id = (json['id']?.toString() ?? '').trim();
    final login = (json['login']?.toString() ?? '').trim();
    final defaultEmail = (json['default_email']?.toString() ?? '').trim();

    return YandexUser(
      id: id,
      login: login,
      defaultEmail: defaultEmail.isEmpty ? null : defaultEmail,
      emails: List<String>.unmodifiable(emails),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'login': login,
      'default_email': defaultEmail ?? '',
      'emails': emails,
    };
  }
}

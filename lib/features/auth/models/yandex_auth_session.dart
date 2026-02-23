import 'yandex_token_response.dart';
import 'yandex_user.dart';

class YandexAuthSession {
  const YandexAuthSession({
    required this.token,
    required this.user,
    required this.createdAtMillis,
  });

  final YandexTokenResponse token;
  final YandexUser user;
  final int createdAtMillis;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'token': token.toJson(),
      'user': user.toJson(),
      'created_at_millis': createdAtMillis,
    };
  }

  factory YandexAuthSession.fromJson(Map<String, dynamic> json) {
    final tokenMap = (json['token'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final userMap = (json['user'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final rawCreatedAt = json['created_at_millis'];
    final createdAt = switch (rawCreatedAt) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    return YandexAuthSession(
      token: YandexTokenResponse.fromJson(tokenMap),
      user: YandexUser.fromJson(userMap),
      createdAtMillis: createdAt,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/auth/models/yandex_user.dart';

void main() {
  test('uses default_email as primary identifier', () {
    final user = YandexUser.fromJson(
      const <String, dynamic>{
        'id': '123',
        'login': 'my_login',
        'default_email': 'user@yandex.ru',
        'emails': <String>['other@yandex.ru'],
      },
    );

    expect(user.bestEmail, 'user@yandex.ru');
    expect(user.identifier, 'user@yandex.ru');
  });

  test('falls back to login when email is unavailable', () {
    final user = YandexUser.fromJson(
      const <String, dynamic>{
        'id': '123',
        'login': 'my_login',
        'default_email': '',
        'emails': <String>[],
      },
    );

    expect(user.bestEmail, isNull);
    expect(user.identifier, 'my_login');
  });

  test('falls back to id when both email and login are unavailable', () {
    final user = YandexUser.fromJson(
      const <String, dynamic>{
        'id': '123',
        'login': '',
        'default_email': null,
        'emails': <String>[],
      },
    );

    expect(user.bestEmail, isNull);
    expect(user.identifier, '123');
  });
}

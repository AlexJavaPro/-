import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/send/send_error_mapper.dart';

void main() {
  test('maps SMTP 535 5.7.8 to no-access user message', () {
    final error = PlatformException(
      code: 'smtp_auth_failed',
      message:
          '535 5.7.8 Error: authentication failed: This user does not have access rights to this service',
    );

    final ui = SendErrorMapper.map(error);

    expect(ui.title, 'Не удалось войти в SMTP Яндекса');
    expect(
      ui.message,
      contains('доступ к SMTP запрещён'),
    );
    expect(
      ui.message,
      contains('нужен пароль приложения'),
    );
    expect(
      ui.message,
      isNot(contains('This user does not have access rights')),
    );
    expect(ui.message.toLowerCase(), isNot(contains('сессия')));
    expect(ui.actionLabel, 'Открыть настройки');
    expect(ui.debugCode, 'SMTP_535_578');
  });

  test('maps SMTP 535 other to invalid-credentials message', () {
    final error = PlatformException(
      code: 'smtp_auth_failed',
      message: '535 5.7.1 authentication failed',
    );

    final ui = SendErrorMapper.map(error);

    expect(ui.title, 'Не удалось войти в SMTP Яндекса');
    expect(ui.message, 'Неверный логин или пароль SMTP.');
    expect(ui.debugCode, 'SMTP_535_AUTH');
  });

  test('maps app auth expired to re-login message', () {
    final error = PlatformException(
      code: 'unauthorized',
      message: 'session expired',
    );

    final ui = SendErrorMapper.map(error);

    expect(ui.message, 'Сессия входа истекла. Войдите в Яндекс заново.');
    expect(ui.debugCode, 'AUTH_SESSION_EXPIRED');
  });
}

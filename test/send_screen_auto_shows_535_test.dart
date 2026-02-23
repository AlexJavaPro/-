import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/send/send_error_mapper.dart';

void main() {
  test('auto mode 535 message is localized and has settings action', () {
    final mapped = SendErrorMapper.map(
      PlatformException(
        code: 'smtp_auth_failed',
        message:
            '535 5.7.8 Error: authentication failed: This user does not have access rights to this service',
      ),
    );

    expect(mapped.title, 'Не удалось войти в SMTP Яндекса');
    expect(
      mapped.message,
      'Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения.',
    );
    expect(mapped.message.contains('This user does not have access rights'), isFalse);
    expect(mapped.actionLabel, 'Открыть настройки');
    expect(mapped.debugCode, 'SMTP_535_578');
  });
}

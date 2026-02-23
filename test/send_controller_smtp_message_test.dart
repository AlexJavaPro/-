import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/send/send_controller.dart';
import 'package:photomailer/features/settings/settings_repository.dart';
import 'package:photomailer/platform/native_bridge.dart';

class _FakeSettingsRepository extends SettingsRepository {}

class _NoopNativeBridge extends NativeBridge {}

void main() {
  SendController createController() {
    return SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _NoopNativeBridge(),
    );
  }

  test('maps SMTP 535 5.7.8 to no-access user message', () {
    final controller = createController();
    final message = controller.mapErrorToMessage(
      PlatformException(
        code: 'smtp_auth_failed',
        message:
            '535 5.7.8 Error: authentication failed: This user does not have access rights to this service',
      ),
    );

    expect(
      message,
      'Не удалось войти в SMTP Яндекса. Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения.',
    );
    controller.dispose();
  });

  test('maps SMTP auth generic to invalid credentials message', () {
    final controller = createController();
    final message = controller.mapErrorToMessage(
      PlatformException(
        code: 'smtp_auth_failed',
        message: '535 5.7.1 Authentication failed',
      ),
    );

    expect(message, 'Неверный логин или пароль SMTP.');
    controller.dispose();
  });

  test('maps password and identity errors', () {
    final controller = createController();
    expect(
      controller.mapErrorToMessage(
        PlatformException(code: 'smtp_password_required'),
      ),
      'Введите пароль приложения Яндекс.',
    );
    expect(
      controller.mapErrorToMessage(
        PlatformException(code: 'smtp_password_invalid'),
      ),
      'Пароль приложения слишком короткий. Минимум 8 символов.',
    );
    expect(
      controller.mapErrorToMessage(
        PlatformException(code: 'smtp_identity_missing'),
      ),
      'Не удалось определить email отправителя. Откройте настройки и войдите в Яндекс заново.',
    );
    controller.dispose();
  });

  test('maps network and app auth errors', () {
    final controller = createController();
    expect(
      controller.mapErrorToMessage(
        PlatformException(code: 'network_error'),
      ),
      'Проверьте интернет. Сервер временно недоступен.',
    );
    expect(
      controller.mapErrorToMessage(
        PlatformException(code: 'unauthorized'),
      ),
      'Сессия входа истекла. Войдите в Яндекс заново.',
    );
    controller.dispose();
  });
}
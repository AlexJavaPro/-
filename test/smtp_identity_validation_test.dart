import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:photomailer/features/photos/photo_model.dart';
import 'package:photomailer/features/send/send_controller.dart';
import 'package:photomailer/features/settings/settings_model.dart';
import 'package:photomailer/features/settings/settings_repository.dart';
import 'package:photomailer/platform/native_bridge.dart';
import 'package:photomailer/platform/native_contract.dart';

class _MockNativeBridge extends Mock implements NativeBridge {}

class _FakeSettingsRepository extends SettingsRepository {
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(<PhotoDescriptor>[]);
  });

  SendController createController(_MockNativeBridge native) {
    return SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    )..settings = AppSettings.defaults().copyWith(
        recipientEmail: 'to@example.com',
        sendMethod: sendMethodOptionId(SendMethodOption.automatic),
        preferredMailClient: mailClientOptionId(MailClientOption.yandex),
        autoSendEnabled: true,
        limitMb: '20',
        subject: 'Фото',
      )
      ..photos = const <PhotoDescriptor>[
        PhotoDescriptor(
          uri: 'content://photo/1',
          name: 'img_1.jpg',
          sizeBytes: 1024,
          mimeType: 'image/jpeg',
        ),
      ];
  }

  test('invalid smtp identity without @ blocks auto sending before enqueue',
      () async {
    final native = _MockNativeBridge();
    final controller = createController(native);
    controller.yandexAuthState = const YandexAuthState(
      authorized: true,
      email: '',
      login: 'sender_login',
      userId: 'uid-1',
      identifier: 'sender_login',
      savedAtMillis: 1,
      smtpReady: true,
      smtpIdentity: 'sender_login',
    );

    await controller.startAutoSending();

    verifyNever(
      () => native.enqueueSendJob(
        recipientEmail: any(named: 'recipientEmail'),
        subjectInput: any(named: 'subjectInput'),
        limitBytes: any(named: 'limitBytes'),
        compressionPreset: any(named: 'compressionPreset'),
        photos: any(named: 'photos'),
      ),
    );
    expect(controller.errorMessage, 'Укажите email для SMTP.');
    expect(controller.canUseAutoMode, isFalse);
  });

  test('empty smtp identity blocks auto sending before enqueue', () async {
    final native = _MockNativeBridge();
    final controller = createController(native);
    controller.yandexAuthState = const YandexAuthState(
      authorized: true,
      email: '',
      login: '',
      userId: 'uid-1',
      identifier: 'uid-1',
      savedAtMillis: 1,
      smtpReady: true,
      smtpIdentity: '',
    );

    await controller.startAutoSending();

    verifyNever(
      () => native.enqueueSendJob(
        recipientEmail: any(named: 'recipientEmail'),
        subjectInput: any(named: 'subjectInput'),
        limitBytes: any(named: 'limitBytes'),
        compressionPreset: any(named: 'compressionPreset'),
        photos: any(named: 'photos'),
      ),
    );
    expect(controller.errorMessage, 'Укажите email для SMTP.');
    expect(controller.canUseAutoMode, isFalse);
  });
}

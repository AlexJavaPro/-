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

  test('auto mode maps SMTP 535 5.7.8 into normalized UI error', () async {
    final native = _MockNativeBridge();
    when(
      () => native.enqueueSendJob(
        recipientEmail: any(named: 'recipientEmail'),
        subjectInput: any(named: 'subjectInput'),
        limitBytes: any(named: 'limitBytes'),
        compressionPreset: any(named: 'compressionPreset'),
        photos: any(named: 'photos'),
      ),
    ).thenAnswer((_) async => 'job-1');
    when(
      () => native.getJobStatus('job-1'),
    ).thenAnswer(
      (_) async => JobStatus(
        jobId: 'job-1',
        state: 'failed',
        sentBatches: 0,
        totalBatches: 3,
        lastError:
            '535 5.7.8 Error: authentication failed: This user does not have access rights to this service',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    when(
      () => native.getJobLogs('job-1', afterId: any(named: 'afterId')),
    ).thenAnswer((_) async => const <LogEntry>[]);

    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );
    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'to@example.com',
      sendMethod: sendMethodOptionId(SendMethodOption.automatic),
      preferredMailClient: mailClientOptionId(MailClientOption.yandex),
      autoSendEnabled: true,
      limitMb: '20',
      subject: 'Фото',
    );
    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'img_1.jpg',
        sizeBytes: 1024,
        mimeType: 'image/jpeg',
      ),
    ];
    controller.yandexAuthState = const YandexAuthState(
      authorized: true,
      email: 'sender@yandex.ru',
      login: 'sender',
      userId: 'uid-1',
      identifier: 'sender@yandex.ru',
      savedAtMillis: 1,
      smtpReady: true,
      smtpIdentity: 'sender@yandex.ru',
    );

    await controller.startAutoSending();

    expect(controller.currentAutoJobStatus?.state, 'failed');
    expect(controller.lastUiError?.debugCode, 'SMTP_535_578');
    expect(
      controller.errorMessage,
      'Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения.',
    );
    verifyNever(() => native.startYandexLogin());
  });
}

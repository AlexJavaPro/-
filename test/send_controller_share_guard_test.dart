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
    registerFallbackValue(const PhotoDescriptor(
      uri: 'content://fallback',
      name: 'fallback.jpg',
      sizeBytes: 1,
      mimeType: 'image/jpeg',
    ));
  });

  test('share flow never calls enqueueSendJob and ignores SMTP 535 state',
      () async {
    final native = _MockNativeBridge();
    when(
      () => native.openExternalEmail(
        photos: any(named: 'photos'),
        subject: any(named: 'subject'),
        recipientEmail: any(named: 'recipientEmail'),
        body: any(named: 'body'),
        chooserTitle: any(named: 'chooserTitle'),
        targetPackage: any(named: 'targetPackage'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => native.getJobStatus(any()),
    ).thenAnswer(
      (_) async => JobStatus(
        jobId: 'legacy-job',
        state: 'failed',
        sentBatches: 0,
        totalBatches: 1,
        lastError:
            '535 5.7.8 Error: authentication failed: This user does not have access rights to this service',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    when(
      () => native.getJobLogs(any(), afterId: any(named: 'afterId')),
    ).thenAnswer((_) async => const <LogEntry>[]);
    when(
      () => native.enqueueSendJob(
        recipientEmail: any(named: 'recipientEmail'),
        subjectInput: any(named: 'subjectInput'),
        limitBytes: any(named: 'limitBytes'),
        compressionPreset: any(named: 'compressionPreset'),
        photos: any(named: 'photos'),
      ),
    ).thenThrow(StateError('enqueue should not be called in share mode'));

    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );

    controller.settings = AppSettings.defaults().copyWith(
      sendMethod: sendMethodOptionId(SendMethodOption.share),
      recipientEmail: 'to@example.com',
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

    await controller.startSending();

    verify(
      () => native.openExternalEmail(
        photos: any(named: 'photos'),
        subject: any(named: 'subject'),
        recipientEmail: any(named: 'recipientEmail'),
        body: any(named: 'body'),
        chooserTitle: any(named: 'chooserTitle'),
        targetPackage: any(named: 'targetPackage'),
      ),
    ).called(1);
    verifyNever(
      () => native.enqueueSendJob(
        recipientEmail: any(named: 'recipientEmail'),
        subjectInput: any(named: 'subjectInput'),
        limitBytes: any(named: 'limitBytes'),
        compressionPreset: any(named: 'compressionPreset'),
        photos: any(named: 'photos'),
      ),
    );

    controller.currentAutoJobId = 'legacy-job';
    await controller.refreshAutoJobStatus(updateMessages: true);

    expect(controller.sendViaShare, isTrue);
    expect(controller.errorMessage, isNull);
    expect(
      controller.infoMessage?.toLowerCase().contains('smtp'),
      isFalse,
    );
    expect(
      controller.infoMessage?.contains('535'),
      isFalse,
    );
    expect(controller.autoSendLastEvent, isEmpty);
  });
}

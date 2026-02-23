import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/photos/photo_model.dart';
import 'package:photomailer/features/send/send_controller.dart';
import 'package:photomailer/features/settings/settings_model.dart';
import 'package:photomailer/features/settings/settings_repository.dart';
import 'package:photomailer/platform/native_bridge.dart';
import 'package:photomailer/platform/native_contract.dart';

class _FakeSettingsRepository extends SettingsRepository {
  AppSettings? lastSaved;

  @override
  Future<void> save(AppSettings settings) async {
    lastSaved = settings;
  }
}

class _FakeNativeBridge extends NativeBridge {
  bool enqueueCalled = false;
  bool selfTestCalled = false;
  bool shareOpened = false;
  String? selfTestRecipient;
  String? selfTestPassword;

  bool failLogin = false;
  bool failSelfTest = false;

  YandexAuthState authState = const YandexAuthState.empty();
  JobStatus? forcedStatus;
  List<LogEntry> forcedLogs = const <LogEntry>[];

  @override
  Future<void> openExternalEmail({
    required List<PhotoDescriptor> photos,
    required String subject,
    String recipientEmail = '',
    String body = '',
    String chooserTitle = 'Выберите почтовое приложение',
    String targetPackage = '',
  }) async {
    shareOpened = true;
  }

  @override
  Future<YandexAuthState> startYandexLogin() async {
    if (failLogin) {
      throw PlatformException(
        code: 'yandex_auth_failed',
        message: 'auth failed',
      );
    }
    return authState;
  }

  @override
  Future<YandexAuthState> getYandexAuthState() async {
    return authState;
  }

  @override
  Future<SmtpSelfTestResult> saveAndRunSmtpSelfTest({
    String? appPassword,
  }) async {
    selfTestCalled = true;
    selfTestPassword = appPassword;
    final recipient = authState.smtpIdentity.isNotEmpty
        ? authState.smtpIdentity
        : authState.email;
    selfTestRecipient = recipient;
    if (failSelfTest) {
      throw PlatformException(
        code: 'smtp_auth_failed',
        message: '535 5.7.8 authentication failed',
      );
    }
    final email =
        authState.email.isNotEmpty ? authState.email : 'sender@yandex.ru';
    final identifier =
        authState.identifier.isNotEmpty ? authState.identifier : email;
    authState = YandexAuthState(
      authorized: true,
      email: email,
      login: email,
      userId: 'user-id',
      identifier: identifier,
      savedAtMillis: DateTime.now().millisecondsSinceEpoch,
      smtpReady: true,
      smtpIdentity: email,
    );
    return SmtpSelfTestResult(
      success: true,
      authMode: appPassword == null ? 'oauth2' : 'app_password',
      recipientEmail: recipient,
      message: 'Тестовое письмо отправлено',
    );
  }

  @override
  Future<String> enqueueSendJob({
    required String recipientEmail,
    required String subjectInput,
    required int limitBytes,
    required String compressionPreset,
    required List<PhotoDescriptor> photos,
  }) async {
    enqueueCalled = true;
    return 'job-1';
  }

  @override
  Future<JobStatus> getJobStatus(String jobId) async {
    return forcedStatus ??
        JobStatus(
          jobId: jobId,
          state: 'running',
          sentBatches: 0,
          totalBatches: 1,
          lastError: null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
  }

  @override
  Future<List<LogEntry>> getJobLogs(
    String jobId, {
    int? afterId,
  }) async {
    return forcedLogs;
  }
}

void main() {
  test('login updates auth state and self-test enables SMTP', () async {
    final native = _FakeNativeBridge()
      ..authState = const YandexAuthState(
        authorized: true,
        email: 'sender@yandex.ru',
        login: 'sender',
        userId: 'uid-1',
        identifier: 'sender@yandex.ru',
        savedAtMillis: 1,
        smtpReady: false,
        smtpIdentity: '',
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );

    await controller.startYandexLogin();
    expect(controller.yandexAuthState.authorized, isTrue);
    expect(controller.yandexAuthState.smtpReady, isFalse);

    await controller.savePasswordAndRunSelfTest('password-1234');
    expect(native.selfTestCalled, isTrue);
    expect(native.selfTestRecipient, 'sender@yandex.ru');
    expect(native.selfTestPassword, 'password1234');
    expect(controller.yandexAuthState.smtpReady, isTrue);
    expect(controller.errorMessage, isNull);
  });

  test('automatic send starts job after login and self-test', () async {
    final native = _FakeNativeBridge()
      ..authState = const YandexAuthState(
        authorized: true,
        email: 'sender@yandex.ru',
        login: 'sender',
        userId: 'uid-1',
        identifier: 'sender@yandex.ru',
        savedAtMillis: 1,
        smtpReady: false,
        smtpIdentity: '',
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'to@example.com',
      sendMethod: 'automatic',
      preferredMailClient: 'yandex',
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

    await controller.startYandexLogin();
    await controller.savePasswordAndRunSelfTest('password-1234');
    await controller.startAutoSending();

    expect(controller.canUseAutoMode, isTrue);
    expect(native.enqueueCalled, isTrue);
    expect(controller.currentAutoJobId, 'job-1');
    expect(controller.currentAutoJobStatus?.state, 'running');
    expect(controller.errorMessage, isNull);
  });

  test('automatic send is blocked without smtpReady', () async {
    final native = _FakeNativeBridge()
      ..authState = const YandexAuthState(
        authorized: true,
        email: 'sender@yandex.ru',
        login: 'sender',
        userId: 'uid-1',
        identifier: 'sender@yandex.ru',
        savedAtMillis: 1,
        smtpReady: false,
        smtpIdentity: '',
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'to@example.com',
      sendMethod: 'automatic',
      preferredMailClient: 'yandex',
      autoSendEnabled: true,
      limitMb: '20',
    );
    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'img_1.jpg',
        sizeBytes: 1024,
        mimeType: 'image/jpeg',
      ),
    ];
    controller.yandexAuthState = native.authState;

    await controller.startAutoSending();

    expect(native.enqueueCalled, isFalse);
    expect(controller.currentAutoJobId, isNull);
    expect(controller.errorMessage, isNotNull);
  });

  test('self-test can run without entering new password when one exists',
      () async {
    final native = _FakeNativeBridge()
      ..authState = const YandexAuthState(
        authorized: true,
        email: 'sender@yandex.ru',
        login: 'sender',
        userId: 'uid-1',
        identifier: 'sender@yandex.ru',
        savedAtMillis: 1,
        smtpReady: false,
        smtpIdentity: 'sender@yandex.ru',
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );
    controller.yandexAuthState = native.authState;
    controller.hasSmtpAppPassword = true;

    await controller.savePasswordAndRunSelfTest('');

    expect(native.selfTestCalled, isTrue);
    expect(native.selfTestPassword, isNull);
    expect(controller.errorMessage, isNull);
    expect(controller.smtpSelfTestSucceeded, isTrue);
  });

  test('share mode ignores failed auto status messages during refresh',
      () async {
    final native = _FakeNativeBridge()
      ..forcedStatus = JobStatus(
        jobId: 'job-legacy',
        state: 'failed',
        sentBatches: 0,
        totalBatches: 1,
        lastError: '535 5.7.8 authentication failed',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );

    controller.settings = controller.settings.copyWith(
      sendMethod: 'share',
      recipientEmail: 'to@example.com',
      limitMb: '20',
    );
    controller.currentAutoJobId = 'job-legacy';

    await controller.refreshAutoJobStatus(updateMessages: true);

    expect(controller.sendViaShare, isTrue);
    expect(controller.errorMessage, isNull);
    expect(controller.currentAutoJobStatus?.state, 'failed');
  });

  test(
      'share flow still opens external mail even with legacy failed auto state',
      () async {
    final native = _FakeNativeBridge()
      ..forcedStatus = JobStatus(
        jobId: 'job-legacy',
        state: 'failed',
        sentBatches: 0,
        totalBatches: 1,
        lastError: '535 5.7.8 authentication failed',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: native,
    );
    controller.currentAutoJobStatus = native.forcedStatus;
    controller.settings = controller.settings.copyWith(
      sendMethod: 'share',
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

    expect(controller.sendViaShare, isTrue);
    expect(native.shareOpened, isTrue);
    expect(controller.errorMessage, isNull);
  });
}

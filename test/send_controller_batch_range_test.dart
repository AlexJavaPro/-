import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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

class _ComposeCall {
  const _ComposeCall({
    required this.subject,
    required this.body,
    required this.recipientEmail,
    required this.targetPackage,
    required this.photosCount,
    required this.photoNames,
  });

  final String subject;
  final String body;
  final String recipientEmail;
  final String targetPackage;
  final int photosCount;
  final List<String> photoNames;
}

class _FakeNativeBridge extends NativeBridge {
  final List<_ComposeCall> calls = <_ComposeCall>[];

  @override
  Future<void> openExternalEmail({
    required List<PhotoDescriptor> photos,
    required String subject,
    String recipientEmail = '',
    String body = '',
    String chooserTitle = '',
    String targetPackage = '',
  }) async {
    calls.add(
      _ComposeCall(
        subject: subject,
        body: body,
        recipientEmail: recipientEmail,
        targetPackage: targetPackage,
        photosCount: photos.length,
        photoNames: photos.map((photo) => photo.name).toList(growable: false),
      ),
    );
  }
}

List<PhotoDescriptor> _threePhotos() {
  return const <PhotoDescriptor>[
    PhotoDescriptor(
      uri: 'content://photo/1',
      name: 'img_1.jpg',
      sizeBytes: 700000,
      mimeType: 'image/jpeg',
    ),
    PhotoDescriptor(
      uri: 'content://photo/2',
      name: 'img_2.jpg',
      sizeBytes: 700000,
      mimeType: 'image/jpeg',
    ),
    PhotoDescriptor(
      uri: 'content://photo/3',
      name: 'img_3.jpg',
      sizeBytes: 700000,
      mimeType: 'image/jpeg',
    ),
  ];
}

void main() {
  test('starts sending only selected range of batches', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
      preferredMailClient: 'system',
    );
    controller.photos = _threePhotos();

    await controller.startSending(startPart: 2, endPart: 3);

    expect(nativeBridge.calls.length, 1);
    expect(nativeBridge.calls.first.subject, contains('Часть 2 из 3'));
    expect(controller.hasActiveBatchSession, isTrue);
    expect(controller.hasRemainingBatches, isTrue);
    expect(controller.nextBatchNumber, 3);

    await controller.openNextBatch();

    expect(nativeBridge.calls.length, 2);
    expect(nativeBridge.calls.last.subject, contains('Часть 3 из 3'));
    expect(controller.hasActiveBatchSession, isFalse);
    expect(controller.hasRemainingBatches, isFalse);
    expect(controller.infoMessage, contains('2-3'));

    controller.dispose();
  });

  test('validates incorrect range before opening external mail app', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
    );
    controller.photos = _threePhotos();

    await controller.startSending(startPart: 3, endPart: 2);

    expect(controller.errorMessage, contains('Неверный диапазон'));
    expect(nativeBridge.calls, isEmpty);
    expect(controller.hasActiveBatchSession, isFalse);

    controller.dispose();
  });

  test('single part mode opens only one selected message', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
    );
    controller.photos = _threePhotos();

    await controller.startSinglePartSending(2);

    expect(nativeBridge.calls.length, 1);
    expect(nativeBridge.calls.first.subject, contains('Часть 2 из 3'));
    expect(controller.hasActiveBatchSession, isFalse);
    expect(controller.infoMessage, contains('2-2'));

    controller.dispose();
  });

  test('uses selected report date in generated subject', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
    );
    controller.photos = _threePhotos();

    await controller.startSending(
      startPart: 1,
      endPart: 1,
      reportDate: DateTime(2024, 12, 31),
    );

    expect(nativeBridge.calls.length, 1);
    expect(nativeBridge.calls.first.subject, contains('от 31.12.2024'));
    expect(nativeBridge.calls.first.body, contains('Размер текущего письма:'));
    expect(nativeBridge.calls.first.body,
        contains('Общий размер выбранных фото:'));
    expect(nativeBridge.calls.first.body, contains('Доля текущего письма:'));
    controller.dispose();
  });

  test('uses today date in subject when report date is not provided', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
    );
    controller.photos = _threePhotos();

    final today = DateFormat('dd.MM.yyyy').format(DateTime.now());
    await controller.startSending(startPart: 1, endPart: 1);

    expect(nativeBridge.calls.length, 1);
    expect(nativeBridge.calls.first.subject, contains('от $today'));
    controller.dispose();
  });

  test('supports descending order by file size for sending', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '100',
      sendOrder: 'size_desc',
    );
    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'small.jpg',
        sizeBytes: 100,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/2',
        name: 'large.jpg',
        sizeBytes: 1000,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/3',
        name: 'mid.jpg',
        sizeBytes: 500,
        mimeType: 'image/jpeg',
      ),
    ];

    await controller.startSending(startPart: 1, endPart: 1);

    expect(nativeBridge.calls, hasLength(1));
    expect(
      nativeBridge.calls.first.photoNames,
      equals(<String>['large.jpg', 'mid.jpg', 'small.jpg']),
    );

    controller.dispose();
  });

  test('estimatedEmailBatchDetails contains full files list and totals',
      () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
      sendOrder: 'added_asc',
    );
    controller.photos = _threePhotos();

    final details = controller.estimatedEmailBatchDetails;

    expect(details, hasLength(3));
    expect(details.first.index, 1);
    expect(details.first.photosCount, 1);
    expect(details.first.totalBytes, 700000);
    expect(details.first.photos.first.name, 'img_1.jpg');
    expect(details[1].photos.first.name, 'img_2.jpg');
    expect(details[2].photos.first.name, 'img_3.jpg');

    controller.dispose();
  });

  test('estimatedEmailBatchDetails respects selected send order', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '100',
      sendOrder: 'size_desc',
    );
    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'small.jpg',
        sizeBytes: 100,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/2',
        name: 'large.jpg',
        sizeBytes: 1000,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/3',
        name: 'mid.jpg',
        sizeBytes: 500,
        mimeType: 'image/jpeg',
      ),
    ];

    final details = controller.estimatedEmailBatchDetails;
    expect(details, hasLength(1));
    expect(
      details.first.photos.map((photo) => photo.name).toList(growable: false),
      equals(<String>['large.jpg', 'mid.jpg', 'small.jpg']),
    );

    controller.dispose();
  });

  test('omits date in subject when includeDate is false', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '1',
    );
    controller.photos = _threePhotos();

    await controller.startSending(
      startPart: 1,
      endPart: 1,
      reportDate: DateTime(2024, 12, 31),
      includeDate: false,
    );

    expect(nativeBridge.calls, hasLength(1));
    expect(nativeBridge.calls.first.subject, startsWith('Фото'));
    expect(nativeBridge.calls.first.subject, isNot(contains('31.12.2024')));

    controller.dispose();
  });

  test('updateSendOrder persists selected order and updates analytics',
      () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      subject: 'Фото',
      limitMb: '100',
      sendOrder: 'added_asc',
    );
    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'small.jpg',
        sizeBytes: 100,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/2',
        name: 'large.jpg',
        sizeBytes: 1000,
        mimeType: 'image/jpeg',
      ),
    ];

    await controller.updateSendOrder(SendOrderOption.sizeDesc);

    expect(controller.settings.sendOrder, 'size_desc');
    expect(repository.lastSaved?.sendOrder, 'size_desc');
    expect(
      controller.orderedPhotos
          .map((photo) => photo.name)
          .toList(growable: false),
      equals(<String>['large.jpg', 'small.jpg']),
    );
    expect(
      controller.estimatedEmailBatchDetails.first.photos
          .map((photo) => photo.name)
          .toList(growable: false),
      equals(<String>['large.jpg', 'small.jpg']),
    );

    controller.dispose();
  });

  test('updatePhotoPickSourceDefault persists selected source', () async {
    final repository = _FakeSettingsRepository();
    final nativeBridge = _FakeNativeBridge();
    final controller = SendController(
      settingsRepository: repository,
      nativeBridge: nativeBridge,
    );

    controller.settings = AppSettings.defaults();
    expect(controller.defaultPhotoPickSource, PhotoPickSource.auto);

    await controller.updatePhotoPickSourceDefault(PhotoPickSource.files);

    expect(controller.settings.photoPickSourceDefault, 'files');
    expect(repository.lastSaved?.photoPickSourceDefault, 'files');
    expect(controller.defaultPhotoPickSource, PhotoPickSource.files);

    controller.dispose();
  });

  test('addedAsc and addedDesc use captured date with insertion fallback', () {
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _FakeNativeBridge(),
    );

    controller.photos = const <PhotoDescriptor>[
      PhotoDescriptor(
        uri: 'content://photo/1',
        name: 'no_date_first.jpg',
        sizeBytes: 10,
        mimeType: 'image/jpeg',
      ),
      PhotoDescriptor(
        uri: 'content://photo/2',
        name: 'newer.jpg',
        sizeBytes: 10,
        mimeType: 'image/jpeg',
        capturedAtMillis: 2000,
      ),
      PhotoDescriptor(
        uri: 'content://photo/3',
        name: 'older.jpg',
        sizeBytes: 10,
        mimeType: 'image/jpeg',
        capturedAtMillis: 1000,
      ),
      PhotoDescriptor(
        uri: 'content://photo/4',
        name: 'no_date_last.jpg',
        sizeBytes: 10,
        mimeType: 'image/jpeg',
      ),
    ];

    controller.settings =
        AppSettings.defaults().copyWith(sendOrder: 'added_asc');
    expect(
      controller.orderedPhotos.map((item) => item.name).toList(growable: false),
      equals(<String>[
        'no_date_first.jpg',
        'older.jpg',
        'newer.jpg',
        'no_date_last.jpg',
      ]),
    );

    controller.settings = controller.settings.copyWith(sendOrder: 'added_desc');
    expect(
      controller.orderedPhotos.map((item) => item.name).toList(growable: false),
      equals(<String>[
        'no_date_last.jpg',
        'newer.jpg',
        'older.jpg',
        'no_date_first.jpg',
      ]),
    );

    controller.dispose();
  });

  test(
      'auto mode requires automatic method, yandex client, enabled toggle and auth',
      () {
    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _FakeNativeBridge(),
    );

    controller.settings = AppSettings.defaults().copyWith(
      recipientEmail: 'recipient@example.com',
      autoSendEnabled: false,
      sendMethod: 'automatic',
      preferredMailClient: 'yandex',
    );
    controller.photos = _threePhotos();
    controller.yandexAuthState = const YandexAuthState(
      authorized: true,
      email: 'sender@yandex.ru',
      login: 'sender',
      userId: 'uid-1',
      identifier: 'sender@yandex.ru',
      savedAtMillis: 1,
      smtpReady: false,
      smtpIdentity: 'sender@yandex.ru',
    );

    expect(controller.canUseAutoMode, isFalse);
    expect(controller.canStartAutoSending, isFalse);

    controller.settings = controller.settings.copyWith(autoSendEnabled: true);
    controller.yandexAuthState = const YandexAuthState(
      authorized: false,
      email: 'sender@yandex.ru',
      login: 'sender',
      userId: 'uid-1',
      identifier: 'sender@yandex.ru',
      savedAtMillis: 1,
      smtpReady: true,
      smtpIdentity: 'sender@yandex.ru',
    );

    expect(controller.canUseAutoMode, isFalse);
    expect(controller.canStartAutoSending, isFalse);

    controller.settings = controller.settings.copyWith(
      sendMethod: 'share',
      preferredMailClient: 'yandex',
    );
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

    expect(controller.canUseAutoMode, isFalse);
    expect(controller.canStartAutoSending, isFalse);

    controller.settings = controller.settings.copyWith(
      sendMethod: 'automatic',
      preferredMailClient: 'system',
    );

    expect(controller.canUseAutoMode, isFalse);
    expect(controller.canStartAutoSending, isFalse);

    controller.settings = controller.settings.copyWith(
      sendMethod: 'automatic',
      preferredMailClient: 'yandex',
    );

    expect(controller.canUseAutoMode, isTrue);
    expect(controller.canStartAutoSending, isTrue);

    controller.dispose();
  });
}

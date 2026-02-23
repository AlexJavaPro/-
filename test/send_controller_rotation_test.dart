import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/photos/photo_model.dart';
import 'package:photomailer/features/send/send_controller.dart';
import 'package:photomailer/features/settings/settings_repository.dart';
import 'package:photomailer/platform/native_bridge.dart';

class _FakeSettingsRepository extends SettingsRepository {}

class _NoopNativeBridge extends NativeBridge {}

void main() {
  test('short tap rotates photo by 90 degrees and cycles after 4 steps', () {
    const photo = PhotoDescriptor(
      uri: 'content://photo/noop/1',
      name: 'photo.jpg',
      sizeBytes: 1024,
      mimeType: 'image/jpeg',
    );

    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _NoopNativeBridge(),
    );
    controller.photos = const <PhotoDescriptor>[photo];

    expect(controller.photoRotateSteps(photo.uri), 0);
    for (var i = 1; i <= 4; i++) {
      controller.rotatePhoto90(photo.uri);
      expect(controller.photoRotateSteps(photo.uri), i % 4);
    }

    controller.dispose();
  });

  test('short tap rotates without changing selection', () {
    const photo = PhotoDescriptor(
      uri: 'content://photo/noop/2',
      name: 'photo2.jpg',
      sizeBytes: 2048,
      mimeType: 'image/jpeg',
    );

    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _NoopNativeBridge(),
    );
    controller.photos = const <PhotoDescriptor>[photo];

    expect(controller.selectedFilesCount, 1);
    controller.rotatePhoto90(photo.uri);
    expect(controller.selectedFilesCount, 1);
    expect(controller.photoRotateSteps(photo.uri), 1);

    controller.dispose();
  });

  test('long press toggles selection without rotating photo', () {
    const photo = PhotoDescriptor(
      uri: 'content://photo/noop/3',
      name: 'photo3.jpg',
      sizeBytes: 2048,
      mimeType: 'image/jpeg',
    );

    final controller = SendController(
      settingsRepository: _FakeSettingsRepository(),
      nativeBridge: _NoopNativeBridge(),
    );
    controller.photos = const <PhotoDescriptor>[photo];

    expect(controller.selectedFilesCount, 1);
    expect(controller.photoRotateSteps(photo.uri), 0);

    controller.onPhotoLongPress(photo.uri);
    expect(controller.selectedFilesCount, 0);
    expect(controller.photoRotateSteps(photo.uri), 0);

    controller.onPhotoLongPress(photo.uri);
    expect(controller.selectedFilesCount, 1);
    expect(controller.photoRotateSteps(photo.uri), 0);

    controller.dispose();
  });
}

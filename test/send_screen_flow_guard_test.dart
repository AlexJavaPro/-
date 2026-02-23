import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send screen keeps returning focus to send card after send/resume', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();

    final resumePattern = RegExp(
      r'didChangeAppLifecycleState[\s\S]*AppLifecycleState\.resumed[\s\S]*_scheduleScrollToSendCard\(animated: false\);',
    );
    final nextBatchPattern = RegExp(
      r'await _controller\.openNextBatch\(\);[\s\S]*_scheduleScrollToSendCard\(\);',
    );
    final startSendPattern = RegExp(
      r'await _controller\.startSending\([\s\S]*\);[\s\S]*_scheduleScrollToSendCard\(\);',
    );

    expect(
      resumePattern.hasMatch(content),
      isTrue,
      reason: 'Missing resume scroll-to-send behavior',
    );
    expect(
      nextBatchPattern.hasMatch(content),
      isTrue,
      reason: 'Manual next-batch action not found',
    );
    expect(
      startSendPattern.hasMatch(content),
      isTrue,
      reason: 'Missing post-start scroll-to-send behavior',
    );
  });

  test('photo action hotspots are isolated from parent tap area', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();
    expect(
      content.contains('behavior: HitTestBehavior.opaque'),
      isTrue,
      reason: 'Expected opaque gesture area for remove control',
    );
    expect(content.contains('onTap: onRemove'), isTrue);
    expect(content.contains('Icons.rotate_right'), isFalse);
    expect(
      RegExp(r'onTap:\s*\(\)\s*=>\s*_controller\.rotatePhoto90\(photo\.uri\)')
          .hasMatch(content),
      isTrue,
    );
    expect(
      RegExp(r'onLongPress:\s*\(\)\s*=>\s*_controller\.onPhotoLongPress\(photo\.uri\)')
          .hasMatch(content),
      isTrue,
    );
  });

  test('status feedback uses top MaterialBanner instead of bottom panel', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();
    expect(content.contains('showMaterialBanner'), isTrue);
    expect(content.contains('MaterialBanner('), isTrue);
    expect(content.contains('bottomNavigationBar:'), isFalse);
    expect(content.contains('_buildStatusPanel('), isFalse);
  });

  test('settings use single self-test action and password saved marker', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();

    expect(content.contains('Сохранить и проверить'), isTrue);
    expect(content.contains('Пароль приложения сохранён'), isTrue);
    expect(content.contains('Изменить пароль'), isTrue);
    expect(content.contains('Параметры письма'), isFalse);

    final saveButtonIndex =
        content.indexOf("label: const Text('Сохранить и проверить')");
    final passwordFieldIndex =
        content.indexOf("labelText: 'Пароль приложения Яндекс'");
    final passwordSavedMarkerIndex =
        content.indexOf("'Пароль приложения сохранён'");
    expect(saveButtonIndex, greaterThan(passwordFieldIndex));
    expect(saveButtonIndex, greaterThan(passwordSavedMarkerIndex));

    final authActionsStart = content.indexOf("label: const Text('Войти')");
    final authActionsEnd = content.indexOf(
        "auth.authorized\n                                ? 'Аккаунт для отправки:");
    expect(authActionsStart, isNonNegative);
    expect(authActionsEnd, greaterThan(authActionsStart));
    final authActionsBlock =
        content.substring(authActionsStart, authActionsEnd);
    expect(
      authActionsBlock.contains('Сохранить и проверить'),
      isFalse,
    );
  });

  test('summary has single total size line and updated size icon', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();

    final totalSizeCount = RegExp('Общий объём:').allMatches(content).length;

    expect(totalSizeCount, 1);
    expect(content.contains('Icons.sd_storage_outlined'), isTrue);
    expect(content.contains('Icons.scale_outlined'), isFalse);
  });

  test(
      'auto send card exposes stage, details and cancel action only in auto mode',
      () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();

    expect(content.contains('Последнее событие:'), isTrue);
    expect(content.contains('Подробнее'), isTrue);
    expect(content.contains('Обновлено:'), isTrue);
    expect(content.contains('Остановить отправку'), isTrue);
    expect(content.contains('if (_usingAutomaticMode && autoStatus != null)'),
        isTrue);
  });
}

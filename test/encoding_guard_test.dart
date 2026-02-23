import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const targets = <String>[
    'lib/features/send/send_screen.dart',
    'lib/features/send/send_controller.dart',
    'lib/features/send/send_error_mapper.dart',
    'lib/features/settings/settings_model.dart',
    'lib/platform/native_bridge.dart',
    'lib/features/auth/yandex_auth_service.dart',
    'android/app/src/main/kotlin/ru/amajo/photomailer/bridge/NativeBridgeHandler.kt',
    'android/app/src/main/kotlin/ru/amajo/photomailer/auth/AuthActivity.kt',
    'android/app/src/main/kotlin/ru/amajo/photomailer/auth/YandexUserInfoApi.kt',
    'android/app/src/main/kotlin/ru/amajo/photomailer/work/SendMailWorker.kt',
    'android/app/src/main/kotlin/ru/amajo/photomailer/files/AttachmentPreparer.kt',
  ];

  const knownMojibakeMarkers = <String>[
    'РљРѕРјСѓ',
    'РђРЅР°Р»РёС‚РёРєР°',
    'РћР±С‰РёР№',
    'РџРѕС‡С‚',
  ];

  final mojibakePattern = RegExp(
    '[\\u0402\\u0403\\u0408\\u0409\\u040A\\u040B\\u040E\\u040F\\u0452\\u0453\\u0458\\u0459\\u045A\\u045B\\u045E\\u045F]',
  );

  test('critical UI/native files do not contain mojibake markers', () {
    for (final path in targets) {
      final content = File(path).readAsStringSync();
      expect(
        content.startsWith('\\ufeff'),
        isFalse,
        reason: 'Unexpected UTF-8 BOM in $path',
      );
      expect(
        mojibakePattern.hasMatch(content),
        isFalse,
        reason: 'Mojibake marker found in $path',
      );
      expect(
        content.contains('????'),
        isFalse,
        reason: 'Placeholder markers found in $path',
      );
      expect(
        content.contains('\\uFFFD'),
        isFalse,
        reason: 'Replacement chars found in $path',
      );
      for (final marker in knownMojibakeMarkers) {
        expect(
          content.contains(marker),
          isFalse,
          reason: 'Known mojibake marker "$marker" found in $path',
        );
      }
    }
  });

  test('critical UI files contain required russian labels', () {
    final sendScreen =
        File('lib/features/send/send_screen.dart').readAsStringSync();
    final sendController =
        File('lib/features/send/send_controller.dart').readAsStringSync();
    final errorMapper =
        File('lib/features/send/send_error_mapper.dart').readAsStringSync();

    expect(sendScreen.contains('Кому'), isTrue);
    expect(sendScreen.contains('Аналитика'), isTrue);
    expect(sendScreen.contains('Отправка сообщения'), isTrue);
    expect(sendScreen.contains('Сохранить и проверить'), isTrue);
    expect(sendScreen.contains('PlatformException('), isFalse);

    expect(sendController.contains('Неверный диапазон'), isTrue);
    expect(errorMapper.contains('SMTP_535_578'), isTrue);
    expect(errorMapper.contains('SMTP Яндекса'), isTrue);
    expect(errorMapper.contains('Введите пароль приложения Яндекс.'), isTrue);
    expect(
      errorMapper.contains(
        'Пароль приложения слишком короткий. Минимум 8 символов.',
      ),
      isTrue,
    );
    expect(sendController.contains('PlatformException('), isFalse);
  });

  test('editor config enforces UTF-8 and LF', () {
    final content = File('.editorconfig').readAsStringSync();
    expect(content.contains('charset = utf-8'), isTrue);
    expect(content.contains('end_of_line = lf'), isTrue);
  });

  test('vscode settings pin UTF-8 for workspace', () {
    final content = File('.vscode/settings.json').readAsStringSync();
    expect(content.contains('"files.encoding": "utf8"'), isTrue);
    expect(content.contains('"files.autoGuessEncoding": false'), isTrue);
  });

  test('gradle enforces UTF-8 JVM encoding', () {
    final content = File('android/gradle.properties').readAsStringSync();
    expect(content.contains('-Dfile.encoding=UTF-8'), isTrue);
  });
}
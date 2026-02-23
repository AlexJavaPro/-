import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('share mode does not render SMTP auto-status block', () {
    final content =
        File('lib/features/send/send_screen.dart').readAsStringSync();

    expect(content.contains('if (_usingAutomaticMode && autoStatus != null)'),
        isTrue);
    expect(content.contains('if (autoUiError != null)'), isTrue);
    expect(content.contains("title: const Text('Подробнее')"), isTrue);
  });
}

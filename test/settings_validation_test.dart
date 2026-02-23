import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/core/validation.dart';

void main() {
  test('accepts valid email', () {
    final error = Validation.validateEmail(
      'user@example.com',
      fieldLabel: 'email',
    );
    expect(error, isNull);
  });

  test('rejects invalid email', () {
    final error = Validation.validateEmail(
      'broken-email',
      fieldLabel: 'email',
    );
    expect(error, isNotNull);
  });

  test('parses limit from mb string', () {
    final bytes = Validation.parseLimitBytesFromMb('20');
    expect(bytes, 20 * 1024 * 1024);
  });

  test('rejects password shorter than 8 chars', () {
    final error = Validation.validatePassword('a1b2c3');
    expect(error, isNotNull);
  });

  test('rejects password without digit', () {
    final error = Validation.validatePassword('abcdefgh');
    expect(error, isNotNull);
  });

  test('accepts password with min length and digit', () {
    final error = Validation.validatePassword('abcd1234');
    expect(error, isNull);
  });

  test('accepts app password without digit', () {
    final error = Validation.validateAppPassword('abcdefghijklmnop');
    expect(error, isNull);
  });

  test('rejects short app password', () {
    final error = Validation.validateAppPassword('short');
    expect(error, isNotNull);
  });
}

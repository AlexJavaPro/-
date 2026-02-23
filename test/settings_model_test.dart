import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/settings/settings_model.dart';

void main() {
  test('defaults include secure-friendly settings', () {
    final settings = AppSettings.defaults();
    expect(settings.limitMb, '25');
    expect(settings.compressionPreset, 'none');
    expect(settings.rememberSenderEmail, isTrue);
    expect(settings.rememberRecipientEmail, isTrue);
    expect(settings.rememberPassword, isTrue);
    expect(settings.autoClearLogBeforeSend, isTrue);
    expect(settings.appLockEnabled, isFalse);
    expect(settings.biometricUnlockEnabled, isTrue);
    expect(settings.patternUnlockEnabled, isFalse);
    expect(settings.sendMethod, 'share');
    expect(settings.sendOrder, 'added_asc');
    expect(settings.photoPickSourceDefault, 'auto');
    expect(settings.autoSendEnabled, isFalse);
  });
}

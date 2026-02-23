import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/settings/settings_model.dart';
import 'package:photomailer/features/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const senderKey = 'settings.sender_email';
  const recipientKey = 'settings.recipient_email';
  const compressionKey = 'settings.compression_preset';
  const sendMethodKey = 'settings.send_method';
  const sendOrderKey = 'settings.send_order';
  const photoSourceKey = 'settings.photo_pick_source_default';
  const autoSendEnabledKey = 'settings.auto_send_enabled';
  const rememberSenderKey = 'settings.remember_sender_email';
  const rememberRecipientKey = 'settings.remember_recipient_email';

  test('load returns empty emails when remember flags are disabled', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      senderKey: 'sender@example.com',
      recipientKey: 'recipient@example.com',
      rememberSenderKey: false,
      rememberRecipientKey: false,
    });
    const repository = SettingsRepository();

    final settings = await repository.load();

    expect(settings.senderEmail, isEmpty);
    expect(settings.recipientEmail, isEmpty);
    expect(settings.rememberSenderEmail, isFalse);
    expect(settings.rememberRecipientEmail, isFalse);
  });

  test('save removes emails from storage when remember flags are disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      senderKey: 'old_sender@example.com',
      recipientKey: 'old_recipient@example.com',
      rememberSenderKey: true,
      rememberRecipientKey: true,
    });
    const repository = SettingsRepository();
    final settings = AppSettings.defaults().copyWith(
      senderEmail: 'new_sender@example.com',
      recipientEmail: 'new_recipient@example.com',
      rememberSenderEmail: false,
      rememberRecipientEmail: false,
    );

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(senderKey), isNull);
    expect(prefs.getString(recipientKey), isNull);
    expect(prefs.getBool(rememberSenderKey), isFalse);
    expect(prefs.getBool(rememberRecipientKey), isFalse);
  });

  test('save persists compression preset', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const repository = SettingsRepository();
    final settings = AppSettings.defaults().copyWith(compressionPreset: 'high');

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(compressionKey), 'high');
  });

  test('save persists send order', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const repository = SettingsRepository();
    final settings = AppSettings.defaults().copyWith(sendOrder: 'size_desc');

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(sendOrderKey), 'size_desc');
  });

  test('save persists send method', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const repository = SettingsRepository();
    final settings = AppSettings.defaults().copyWith(sendMethod: 'automatic');

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(sendMethodKey), 'automatic');
  });

  test('save persists default photo pick source', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const repository = SettingsRepository();
    final settings =
        AppSettings.defaults().copyWith(photoPickSourceDefault: 'files');

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(photoSourceKey), 'files');
  });

  test('save persists auto send enabled flag', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const repository = SettingsRepository();
    final settings = AppSettings.defaults().copyWith(autoSendEnabled: true);

    await repository.save(settings);
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getBool(autoSendEnabledKey), isTrue);
  });
}

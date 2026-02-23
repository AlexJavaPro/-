import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import 'settings_model.dart';

class SettingsRepository {
  const SettingsRepository();

  static const _senderKey = 'settings.sender_email';
  static const _recipientKey = 'settings.recipient_email';
  static const _subjectKey = 'settings.subject';
  static const _limitKey = 'settings.limit_mb';
  static const _compressionPresetKey = 'settings.compression_preset';
  static const _rememberSenderEmailKey = 'settings.remember_sender_email';
  static const _rememberRecipientEmailKey = 'settings.remember_recipient_email';
  static const _rememberPasswordKey = 'settings.remember_password';
  static const _autoClearLogKey = 'settings.auto_clear_log_before_send';
  static const _appLockEnabledKey = 'settings.app_lock_enabled';
  static const _biometricUnlockEnabledKey = 'settings.biometric_unlock_enabled';
  static const _patternUnlockEnabledKey = 'settings.pattern_unlock_enabled';
  static const _preferredMailClientKey = 'settings.preferred_mail_client';
  static const _sendMethodKey = 'settings.send_method';
  static const _sendOrderKey = 'settings.send_order';
  static const _photoPickSourceDefaultKey =
      'settings.photo_pick_source_default';
  static const _autoSendEnabledKey = 'settings.auto_send_enabled';
  static const _galleryPermissionPromptedOnceKey =
      'settings.gallery_permission_prompted_once';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberSender = prefs.getBool(_rememberSenderEmailKey) ?? true;
    final rememberRecipient = prefs.getBool(_rememberRecipientEmailKey) ?? true;

    return AppSettings(
      senderEmail: rememberSender ? (prefs.getString(_senderKey) ?? '') : '',
      recipientEmail:
          rememberRecipient ? (prefs.getString(_recipientKey) ?? '') : '',
      subject: prefs.getString(_subjectKey) ?? '\u0424\u043e\u0442\u043e',
      limitMb: prefs.getString(_limitKey) ?? '${AppConstants.defaultLimitMb}',
      compressionPreset: prefs.getString(_compressionPresetKey) ?? 'none',
      rememberSenderEmail: rememberSender,
      rememberRecipientEmail: rememberRecipient,
      rememberPassword: prefs.getBool(_rememberPasswordKey) ?? true,
      autoClearLogBeforeSend: prefs.getBool(_autoClearLogKey) ?? true,
      appLockEnabled: prefs.getBool(_appLockEnabledKey) ?? false,
      biometricUnlockEnabled: prefs.getBool(_biometricUnlockEnabledKey) ?? true,
      patternUnlockEnabled: prefs.getBool(_patternUnlockEnabledKey) ?? false,
      preferredMailClient: prefs.getString(_preferredMailClientKey) ?? 'yandex',
      sendMethod: sendMethodOptionId(
        sendMethodOptionFromId(prefs.getString(_sendMethodKey) ?? 'share'),
      ),
      sendOrder: sendOrderOptionId(
        sendOrderOptionFromId(prefs.getString(_sendOrderKey) ?? 'added_asc'),
      ),
      photoPickSourceDefault: normalizePhotoPickSourceDefault(
        prefs.getString(_photoPickSourceDefaultKey) ?? 'auto',
      ),
      autoSendEnabled: prefs.getBool(_autoSendEnabledKey) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    if (settings.rememberSenderEmail) {
      await prefs.setString(_senderKey, settings.senderEmail.trim());
    } else {
      await prefs.remove(_senderKey);
    }

    if (settings.rememberRecipientEmail) {
      await prefs.setString(_recipientKey, settings.recipientEmail.trim());
    } else {
      await prefs.remove(_recipientKey);
    }

    await prefs.setString(_subjectKey, settings.subject.trim());
    await prefs.setString(_limitKey, settings.limitMb.trim());
    await prefs.setString(
        _compressionPresetKey, settings.compressionPreset.trim());
    await prefs.setBool(_rememberSenderEmailKey, settings.rememberSenderEmail);
    await prefs.setBool(
        _rememberRecipientEmailKey, settings.rememberRecipientEmail);
    await prefs.setBool(_rememberPasswordKey, settings.rememberPassword);
    await prefs.setBool(_autoClearLogKey, settings.autoClearLogBeforeSend);
    await prefs.setBool(_appLockEnabledKey, settings.appLockEnabled);
    await prefs.setBool(
        _biometricUnlockEnabledKey, settings.biometricUnlockEnabled);
    await prefs.setBool(
        _patternUnlockEnabledKey, settings.patternUnlockEnabled);
    await prefs.setString(
      _preferredMailClientKey,
      settings.preferredMailClient.trim().toLowerCase(),
    );
    await prefs.setString(
      _sendMethodKey,
      sendMethodOptionId(sendMethodOptionFromId(settings.sendMethod)),
    );
    await prefs.setString(
      _sendOrderKey,
      sendOrderOptionId(sendOrderOptionFromId(settings.sendOrder)),
    );
    await prefs.setString(
      _photoPickSourceDefaultKey,
      normalizePhotoPickSourceDefault(settings.photoPickSourceDefault),
    );
    await prefs.setBool(_autoSendEnabledKey, settings.autoSendEnabled);
  }

  Future<bool> loadGalleryPermissionPromptedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_galleryPermissionPromptedOnceKey) ?? false;
  }

  Future<void> markGalleryPermissionPromptedOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_galleryPermissionPromptedOnceKey, true);
  }
}

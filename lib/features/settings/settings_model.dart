import '../../core/constants.dart';

enum SendMethodOption {
  share,
  automatic,
}

SendMethodOption sendMethodOptionFromId(String value) {
  switch (value.trim().toLowerCase()) {
    case 'automatic':
      return SendMethodOption.automatic;
    case 'share':
    default:
      return SendMethodOption.share;
  }
}

String sendMethodOptionId(SendMethodOption option) {
  switch (option) {
    case SendMethodOption.share:
      return 'share';
    case SendMethodOption.automatic:
      return 'automatic';
  }
}

String sendMethodOptionLabel(SendMethodOption option) {
  switch (option) {
    case SendMethodOption.share:
      return 'Поделиться';
    case SendMethodOption.automatic:
      return 'Автоматически';
  }
}

enum MailClientOption {
  system,
  yandex,
}

MailClientOption mailClientOptionFromId(String value) {
  switch (value.trim().toLowerCase()) {
    case 'yandex':
      return MailClientOption.yandex;
    case 'system':
    default:
      return MailClientOption.system;
  }
}

String mailClientOptionId(MailClientOption option) {
  switch (option) {
    case MailClientOption.system:
      return 'system';
    case MailClientOption.yandex:
      return 'yandex';
  }
}

String mailClientOptionLabel(MailClientOption option) {
  switch (option) {
    case MailClientOption.system:
      return 'Системный выбор';
    case MailClientOption.yandex:
      return 'Яндекс Почта';
  }
}

String? mailClientPackageName(MailClientOption option) {
  switch (option) {
    case MailClientOption.system:
      return null;
    case MailClientOption.yandex:
      return 'ru.yandex.mail';
  }
}

enum SendOrderOption {
  addedAsc,
  addedDesc,
  sizeAsc,
  sizeDesc,
}

String normalizePhotoPickSourceDefault(String value) {
  switch (value.trim().toLowerCase()) {
    case 'gallery':
      return 'gallery';
    case 'files':
      return 'files';
    case 'auto':
    default:
      return 'auto';
  }
}

SendOrderOption sendOrderOptionFromId(String value) {
  switch (value.trim().toLowerCase()) {
    case 'added_desc':
      return SendOrderOption.addedDesc;
    case 'size_asc':
      return SendOrderOption.sizeAsc;
    case 'size_desc':
      return SendOrderOption.sizeDesc;
    case 'added_asc':
    default:
      return SendOrderOption.addedAsc;
  }
}

String sendOrderOptionId(SendOrderOption option) {
  switch (option) {
    case SendOrderOption.addedAsc:
      return 'added_asc';
    case SendOrderOption.addedDesc:
      return 'added_desc';
    case SendOrderOption.sizeAsc:
      return 'size_asc';
    case SendOrderOption.sizeDesc:
      return 'size_desc';
  }
}

String sendOrderOptionLabel(SendOrderOption option) {
  switch (option) {
    case SendOrderOption.addedAsc:
      return 'Сначала старые (по дате)';
    case SendOrderOption.addedDesc:
      return 'Сначала новые (по дате)';
    case SendOrderOption.sizeAsc:
      return 'Сначала маленькие (по размеру)';
    case SendOrderOption.sizeDesc:
      return 'Сначала большие (по размеру)';
  }
}

// ── Compression ─────────────────────────────────────────────────────────────

enum CompressionPreset {
  none,
  jpegLight,
  jpegMedium,
  jpegStrong,
  webpLight,
  webpMedium,
}

CompressionPreset compressionPresetFromId(String value) {
  switch (value.trim().toLowerCase()) {
    case 'jpeg_light':
      return CompressionPreset.jpegLight;
    case 'jpeg_medium':
      return CompressionPreset.jpegMedium;
    case 'jpeg_strong':
      return CompressionPreset.jpegStrong;
    case 'webp_light':
      return CompressionPreset.webpLight;
    case 'webp_medium':
      return CompressionPreset.webpMedium;
    case 'none':
    default:
      return CompressionPreset.none;
  }
}

String compressionPresetId(CompressionPreset preset) {
  switch (preset) {
    case CompressionPreset.none:
      return 'none';
    case CompressionPreset.jpegLight:
      return 'jpeg_light';
    case CompressionPreset.jpegMedium:
      return 'jpeg_medium';
    case CompressionPreset.jpegStrong:
      return 'jpeg_strong';
    case CompressionPreset.webpLight:
      return 'webp_light';
    case CompressionPreset.webpMedium:
      return 'webp_medium';
  }
}

String compressionPresetLabel(CompressionPreset preset) {
  switch (preset) {
    case CompressionPreset.none:
      return 'Без сжатия (оригинал)';
    case CompressionPreset.jpegLight:
      return 'JPEG лёгкое (85%, до 2560px)';
    case CompressionPreset.jpegMedium:
      return 'JPEG среднее (68%, до 1920px)';
    case CompressionPreset.jpegStrong:
      return 'JPEG сильное (50%, до 1280px)';
    case CompressionPreset.webpLight:
      return 'WebP лёгкое (85%, до 2560px)';
    case CompressionPreset.webpMedium:
      return 'WebP среднее (65%, до 1920px)';
  }
}

String compressionPresetDescription(CompressionPreset preset) {
  switch (preset) {
    case CompressionPreset.none:
      return 'Файлы отправляются без изменений';
    case CompressionPreset.jpegLight:
      return 'Небольшое сжатие, качество почти не теряется';
    case CompressionPreset.jpegMedium:
      return 'Оптимальный баланс качества и размера';
    case CompressionPreset.jpegStrong:
      return 'Максимальное уменьшение файла';
    case CompressionPreset.webpLight:
      return 'WebP формат, лёгкое сжатие (современный формат)';
    case CompressionPreset.webpMedium:
      return 'WebP формат, среднее сжатие';
  }
}

class AppSettings {
  const AppSettings({
    required this.senderEmail,
    required this.recipientEmail,
    required this.subject,
    required this.limitMb,
    required this.compressionPreset,
    required this.rememberSenderEmail,
    required this.rememberRecipientEmail,
    required this.rememberPassword,
    required this.autoClearLogBeforeSend,
    required this.appLockEnabled,
    required this.biometricUnlockEnabled,
    required this.patternUnlockEnabled,
    required this.preferredMailClient,
    required this.sendMethod,
    required this.sendOrder,
    required this.photoPickSourceDefault,
    required this.autoSendEnabled,
  });

  factory AppSettings.defaults() => const AppSettings(
        senderEmail: '',
        recipientEmail: '',
        subject: '\u0424\u043e\u0442\u043e',
        limitMb: '${AppConstants.defaultLimitMb}',
        compressionPreset: 'none',
        rememberSenderEmail: true,
        rememberRecipientEmail: true,
        rememberPassword: true,
        autoClearLogBeforeSend: true,
        appLockEnabled: false,
        biometricUnlockEnabled: true,
        patternUnlockEnabled: false,
        preferredMailClient: 'yandex',
        sendMethod: 'share',
        sendOrder: 'added_asc',
        photoPickSourceDefault: 'auto',
        autoSendEnabled: false,
      );

  final String senderEmail;
  final String recipientEmail;
  final String subject;
  final String limitMb;
  final String compressionPreset;
  final bool rememberSenderEmail;
  final bool rememberRecipientEmail;
  final bool rememberPassword;
  final bool autoClearLogBeforeSend;
  final bool appLockEnabled;
  final bool biometricUnlockEnabled;
  final bool patternUnlockEnabled;
  final String preferredMailClient;
  final String sendMethod;
  final String sendOrder;
  final String photoPickSourceDefault;
  final bool autoSendEnabled;

  AppSettings copyWith({
    String? senderEmail,
    String? recipientEmail,
    String? subject,
    String? limitMb,
    String? compressionPreset,
    bool? rememberSenderEmail,
    bool? rememberRecipientEmail,
    bool? rememberPassword,
    bool? autoClearLogBeforeSend,
    bool? appLockEnabled,
    bool? biometricUnlockEnabled,
    bool? patternUnlockEnabled,
    String? preferredMailClient,
    String? sendMethod,
    String? sendOrder,
    String? photoPickSourceDefault,
    bool? autoSendEnabled,
  }) {
    return AppSettings(
      senderEmail: senderEmail ?? this.senderEmail,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      subject: subject ?? this.subject,
      limitMb: limitMb ?? this.limitMb,
      compressionPreset: compressionPreset ?? this.compressionPreset,
      rememberSenderEmail: rememberSenderEmail ?? this.rememberSenderEmail,
      rememberRecipientEmail:
          rememberRecipientEmail ?? this.rememberRecipientEmail,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      autoClearLogBeforeSend:
          autoClearLogBeforeSend ?? this.autoClearLogBeforeSend,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricUnlockEnabled:
          biometricUnlockEnabled ?? this.biometricUnlockEnabled,
      patternUnlockEnabled: patternUnlockEnabled ?? this.patternUnlockEnabled,
      preferredMailClient: preferredMailClient ?? this.preferredMailClient,
      sendMethod: sendMethod ?? this.sendMethod,
      sendOrder: sendOrder ?? this.sendOrder,
      photoPickSourceDefault:
          photoPickSourceDefault ?? this.photoPickSourceDefault,
      autoSendEnabled: autoSendEnabled ?? this.autoSendEnabled,
    );
  }
}

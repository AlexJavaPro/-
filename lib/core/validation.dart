class Validation {
  Validation._();

  static const int passwordMinLength = 8;

  static final RegExp _emailPattern = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );
  static final RegExp _digitPattern = RegExp(r'\d');

  static String? validateEmail(String value, {required String fieldLabel}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Введите $fieldLabel';
    }
    if (!_emailPattern.hasMatch(normalized)) {
      return 'Некорректный формат: $fieldLabel';
    }
    return null;
  }

  static int? parseLimitBytesFromMb(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(normalized);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return (parsed * 1024 * 1024).round();
  }

  static String? validateLimitMb(String raw) {
    final bytes = parseLimitBytesFromMb(raw);
    if (bytes == null) {
      return 'Укажите корректный лимит в МБ';
    }
    final mb = bytes / (1024 * 1024);
    if (mb < 1 || mb > 200) {
      return 'Лимит должен быть от 1 до 200 МБ';
    }
    return null;
  }

  static String? validatePassword(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Введите пароль приложения';
    }
    if (!hasMinPasswordLength(normalized)) {
      return 'Пароль: минимум $passwordMinLength символов';
    }
    if (!hasPasswordDigit(normalized)) {
      return 'Пароль: нужна хотя бы одна цифра';
    }
    return null;
  }

  static String? validateAppPassword(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'Введите пароль приложения';
    }
    if (!hasMinPasswordLength(normalized)) {
      return 'Пароль приложения: минимум $passwordMinLength символов';
    }
    return null;
  }

  static bool hasMinPasswordLength(String value) {
    return value.trim().length >= passwordMinLength;
  }

  static bool hasPasswordDigit(String value) {
    return _digitPattern.hasMatch(value.trim());
  }
}

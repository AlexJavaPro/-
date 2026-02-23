import 'dart:io';

import 'package:flutter/services.dart';

class UiError {
  const UiError({
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionRoute,
    this.debugCode,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final String? actionRoute;
  final String? debugCode;

  bool get hasAction =>
      actionLabel != null &&
      actionLabel!.trim().isNotEmpty &&
      actionRoute != null &&
      actionRoute!.trim().isNotEmpty;
}

class SendErrorMapper {
  SendErrorMapper._();

  static const String openSendSettingsRoute = 'send_settings';

  static UiError map(Object error) {
    final snapshot = _snapshot(error);

    if (_isSmtpNoAccess(snapshot)) {
      return const UiError(
        title: 'Не удалось войти в SMTP Яндекса',
        message:
            'Для этого аккаунта доступ к SMTP запрещён или нужен пароль приложения.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'SMTP_535_578',
      );
    }

    if (_isSmtpAuth(snapshot)) {
      return const UiError(
        title: 'Не удалось войти в SMTP Яндекса',
        message: 'Неверный логин или пароль SMTP.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'SMTP_535_AUTH',
      );
    }

    if (snapshot.code == 'smtp_password_required') {
      return const UiError(
        title: 'Пароль приложения не указан',
        message: 'Введите пароль приложения Яндекс.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'SMTP_PASSWORD_REQUIRED',
      );
    }

    if (snapshot.code == 'smtp_password_invalid') {
      return const UiError(
        title: 'Некорректный пароль приложения',
        message: 'Пароль приложения слишком короткий. Минимум 8 символов.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'SMTP_PASSWORD_INVALID',
      );
    }

    if (snapshot.code == 'smtp_identity_missing') {
      return const UiError(
        title: 'Не найден SMTP email',
        message:
            'Не удалось определить email отправителя. Откройте настройки и войдите в Яндекс заново.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'SMTP_IDENTITY_MISSING',
      );
    }

    if (snapshot.code == 'validation_error') {
      return const UiError(
        title: 'Проверьте данные',
        message: 'Укажите корректный адрес получателя.',
        debugCode: 'VALIDATION_ERROR',
      );
    }

    if (_isAppAuthExpired(snapshot)) {
      return const UiError(
        title: 'Требуется вход в Яндекс',
        message: 'Сессия входа истекла. Войдите в Яндекс заново.',
        actionLabel: 'Открыть настройки',
        actionRoute: openSendSettingsRoute,
        debugCode: 'AUTH_SESSION_EXPIRED',
      );
    }

    if (_isNetwork(snapshot)) {
      return const UiError(
        title: 'Сетевая ошибка',
        message: 'Проверьте интернет. Сервер временно недоступен.',
        debugCode: 'NETWORK_ERROR',
      );
    }

    if (snapshot.code == 'picker_launch_failed') {
      return const UiError(
        title: 'Галерея недоступна',
        message: 'Не удалось открыть галерею. Попробуйте позже.',
        debugCode: 'PICKER_LAUNCH_FAILED',
      );
    }

    return const UiError(
      title: 'Ошибка',
      message: 'Произошла ошибка. Повторите попытку.',
      debugCode: 'UNKNOWN',
    );
  }

  static bool _isSmtpNoAccess(_ErrorSnapshot snapshot) {
    return snapshot.contains('smtp_535_578') ||
        snapshot.contains('5.7.8') ||
        snapshot.contains('this user does not have access rights to this service') ||
        snapshot.contains('smtp_auth_failed:no_access');
  }

  static bool _isSmtpAuth(_ErrorSnapshot snapshot) {
    return snapshot.code == 'smtp_auth_failed' ||
        snapshot.contains('smtp_auth_failed') ||
        snapshot.contains('authenticationfailedexception') ||
        snapshot.contains('authentication failed') ||
        snapshot.contains('535');
  }

  static bool _isAppAuthExpired(_ErrorSnapshot snapshot) {
    return snapshot.code == 'unauthorized' ||
        snapshot.contains('session expired') ||
        snapshot.contains('oauth') &&
            (snapshot.contains('expired') || snapshot.contains('unauthorized'));
  }

  static bool _isNetwork(_ErrorSnapshot snapshot) {
    if (snapshot.error is SocketException) {
      return true;
    }
    return snapshot.code.contains('network') ||
        snapshot.code.contains('timeout') ||
        snapshot.code.contains('host') ||
        snapshot.contains('network') ||
        snapshot.contains('timeout') ||
        snapshot.contains('socket') ||
        snapshot.contains('unknownhost');
  }

  static _ErrorSnapshot _snapshot(Object error) {
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final message = (error.message ?? '').trim().toLowerCase();
      return _ErrorSnapshot(error: error, code: code, text: '$code $message');
    }
    final text = error.toString().trim().toLowerCase();
    return _ErrorSnapshot(error: error, code: '', text: text);
  }
}

class _ErrorSnapshot {
  const _ErrorSnapshot({
    required this.error,
    required this.code,
    required this.text,
  });

  final Object error;
  final String code;
  final String text;

  bool contains(String value) => text.contains(value.toLowerCase());
}

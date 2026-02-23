import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/yandex_auth_session.dart';
import 'yandex_auth_exception.dart';
import 'yandex_auth_service.dart';

class YandexAuthRepository {
  YandexAuthRepository({
    required YandexAuthService authService,
    FlutterSecureStorage? secureStorage,
  })  : _authService = authService,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final YandexAuthService _authService;
  final FlutterSecureStorage _secureStorage;

  Future<YandexAuthSession> signIn() async {
    final session = await _authService.signInWithPkce();
    await saveSession(session);
    return session;
  }

  Future<void> saveSession(YandexAuthSession session) async {
    try {
      await _secureStorage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
    } on Exception catch (error) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.storage,
        message: 'Failed to save Yandex session',
        cause: error,
      );
    }
  }

  Future<YandexAuthSession?> readSession() async {
    try {
      final raw = await _secureStorage.read(key: _sessionKey);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final mapped = decoded.cast<String, dynamic>();
      final session = YandexAuthSession.fromJson(mapped);
      if (session.token.accessToken.isEmpty || session.user.identifier.isEmpty) {
        return null;
      }
      return session;
    } on Exception catch (error) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.storage,
        message: 'Failed to read Yandex session',
        cause: error,
      );
    }
  }

  Future<void> clearSession() async {
    try {
      await _secureStorage.delete(key: _sessionKey);
    } on Exception catch (error) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.storage,
        message: 'Failed to clear Yandex session',
        cause: error,
      );
    }
  }

  static const String _sessionKey = 'yandex_auth_session_v1';
}

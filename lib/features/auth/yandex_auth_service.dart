import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'models/yandex_auth_session.dart';
import 'models/yandex_token_response.dart';
import 'models/yandex_user.dart';
import 'yandex_auth_exception.dart';

class YandexOAuthConfig {
  const YandexOAuthConfig({
    required this.clientId,
    required this.redirectUri,
    this.scopes = const <String>{'login:email', 'login:info'},
    this.authorizeEndpoint = 'https://oauth.yandex.ru/authorize',
    this.tokenEndpoint = 'https://oauth.yandex.ru/token',
    this.userInfoEndpoint = 'https://login.yandex.ru/info?format=json',
  });

  final String clientId;
  final String redirectUri;
  final Set<String> scopes;
  final String authorizeEndpoint;
  final String tokenEndpoint;
  final String userInfoEndpoint;
}

class YandexAuthService {
  YandexAuthService({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final YandexOAuthConfig config;
  final http.Client _httpClient;

  Future<YandexAuthSession> signInWithPkce() async {
    final codeVerifier = _generateRandomUrlSafe(96);
    final codeChallenge = _createCodeChallengeS256(codeVerifier);
    final state = _generateRandomUrlSafe(32);

    final redirectUri = Uri.parse(config.redirectUri);
    final authUri = Uri.parse(config.authorizeEndpoint).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final callbackUrl = await _authenticate(
      authorizationUrl: authUri.toString(),
      callbackScheme: redirectUri.scheme,
    );
    final callbackUri = Uri.parse(callbackUrl);

    final callbackState = callbackUri.queryParameters['state']?.trim();
    if (callbackState != state) {
      throw const YandexAuthException(
        code: YandexAuthErrorCode.invalidState,
        message: 'OAuth state mismatch',
      );
    }

    final code = (callbackUri.queryParameters['code'] ?? '').trim();
    if (code.isEmpty) {
      final description = callbackUri.queryParameters['error_description'] ??
          callbackUri.queryParameters['error'] ??
          'Authorization code is missing';
      throw YandexAuthException(
        code: YandexAuthErrorCode.oauthFailed,
        message: description,
      );
    }

    final token = await _exchangeCodeForToken(
      code: code,
      codeVerifier: codeVerifier,
      redirectUri: config.redirectUri,
    );
    final user = await fetchUserProfile(token.accessToken);

    if (user.identifier.isEmpty) {
      throw const YandexAuthException(
        code: YandexAuthErrorCode.profileUnavailable,
        message: 'Yandex profile does not contain usable id/login/email',
      );
    }

    return YandexAuthSession(
      token: token,
      user: user,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<YandexUser> fetchUserProfile(String accessToken) async {
    if (accessToken.trim().isEmpty) {
      throw const YandexAuthException(
        code: YandexAuthErrorCode.invalidToken,
        message: 'Access token is empty',
      );
    }
    final request = http.Request('GET', Uri.parse(config.userInfoEndpoint))
      ..headers['Authorization'] = 'OAuth $accessToken';

    late http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } on Exception catch (error) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.network,
        message: 'Network error while loading Yandex profile',
        cause: error,
      );
    }

    final body = await response.stream.bytesToString();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const YandexAuthException(
        code: YandexAuthErrorCode.invalidToken,
        message: 'Yandex token is invalid or expired',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.profileUnavailable,
        message: 'Failed to load Yandex profile (HTTP ${response.statusCode})',
      );
    }

    final decoded = _decodeJsonMap(body);
    return YandexUser.fromJson(decoded);
  }

  Future<YandexTokenResponse> _exchangeCodeForToken({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final request = http.Request('POST', Uri.parse(config.tokenEndpoint))
      ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
      ..bodyFields = <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': config.clientId,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      };

    late http.StreamedResponse response;
    try {
      response = await _httpClient.send(request);
    } on Exception catch (error) {
      throw YandexAuthException(
        code: YandexAuthErrorCode.network,
        message: 'Network error while exchanging OAuth code',
        cause: error,
      );
    }

    final body = await response.stream.bytesToString();
    final parsed = _decodeJsonMap(body, fallback: const <String, dynamic>{});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (parsed['error_description']?.toString() ?? '').trim();
      throw YandexAuthException(
        code: YandexAuthErrorCode.oauthFailed,
        message: message.isNotEmpty
            ? message
            : 'OAuth token exchange failed (HTTP ${response.statusCode})',
      );
    }

    final token = YandexTokenResponse.fromJson(parsed);
    if (token.accessToken.isEmpty) {
      throw const YandexAuthException(
        code: YandexAuthErrorCode.oauthFailed,
        message: 'OAuth response does not contain access_token',
      );
    }
    return token;
  }

  Future<String> _authenticate({
    required String authorizationUrl,
    required String callbackScheme,
  }) async {
    try {
      return await FlutterWebAuth2.authenticate(
        url: authorizationUrl,
        callbackUrlScheme: callbackScheme,
      );
    } on Exception catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('canceled') || message.contains('cancelled')) {
        throw YandexAuthException(
          code: YandexAuthErrorCode.cancelled,
          message: 'Authorization was cancelled',
          cause: error,
        );
      }
      throw YandexAuthException(
        code: YandexAuthErrorCode.oauthFailed,
        message: 'Failed to complete OAuth authentication',
        cause: error,
      );
    }
  }

  Map<String, dynamic> _decodeJsonMap(
    String raw, {
    Map<String, dynamic>? fallback,
  }) {
    if (raw.trim().isEmpty) {
      return fallback ??
          (throw const YandexAuthException(
            code: YandexAuthErrorCode.unknown,
            message: 'Empty JSON response',
          ));
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      throw const YandexAuthException(
        code: YandexAuthErrorCode.unknown,
        message: 'Unexpected JSON payload',
      );
    } on YandexAuthException {
      rethrow;
    } on Exception catch (error) {
      if (fallback != null) {
        return fallback;
      }
      throw YandexAuthException(
        code: YandexAuthErrorCode.unknown,
        message: 'Invalid JSON response',
        cause: error,
      );
    }
  }

  String _generateRandomUrlSafe(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String _createCodeChallengeS256(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

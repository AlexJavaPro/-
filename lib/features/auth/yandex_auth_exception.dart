enum YandexAuthErrorCode {
  cancelled,
  invalidState,
  oauthFailed,
  invalidToken,
  profileUnavailable,
  network,
  storage,
  unknown,
}

class YandexAuthException implements Exception {
  const YandexAuthException({
    required this.code,
    required this.message,
    this.cause,
  });

  final YandexAuthErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'YandexAuthException($code, $message)';
}

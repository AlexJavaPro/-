class YandexTokenResponse {
  const YandexTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresInSeconds,
    required this.scope,
    this.refreshToken,
  });

  final String accessToken;
  final String tokenType;
  final int? expiresInSeconds;
  final String scope;
  final String? refreshToken;

  factory YandexTokenResponse.fromJson(Map<String, dynamic> json) {
    int? expires;
    final rawExpires = json['expires_in'];
    if (rawExpires is num) {
      expires = rawExpires.toInt();
    } else if (rawExpires is String) {
      expires = int.tryParse(rawExpires);
    }

    final refresh = (json['refresh_token']?.toString() ?? '').trim();
    return YandexTokenResponse(
      accessToken: (json['access_token']?.toString() ?? '').trim(),
      tokenType: (json['token_type']?.toString() ?? '').trim(),
      expiresInSeconds: expires,
      scope: (json['scope']?.toString() ?? '').trim(),
      refreshToken: refresh.isEmpty ? null : refresh,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'access_token': accessToken,
      'token_type': tokenType,
      'expires_in': expiresInSeconds,
      'scope': scope,
      'refresh_token': refreshToken,
    };
  }
}

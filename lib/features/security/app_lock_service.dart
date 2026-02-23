import 'package:local_auth/local_auth.dart';

import '../../platform/native_bridge.dart';

class AppLockService {
  AppLockService({
    NativeBridge? nativeBridge,
    LocalAuthentication? localAuthentication,
  })  : _nativeBridge = nativeBridge ?? const NativeBridge(),
        _localAuth = localAuthentication ?? LocalAuthentication();

  final NativeBridge _nativeBridge;
  final LocalAuthentication _localAuth;

  Future<bool> canUseBiometric() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        return false;
      }
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Подтвердите вход в приложение',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> savePattern(String pattern) {
    return _nativeBridge.saveAppPattern(pattern);
  }

  Future<bool> verifyPattern(String pattern) {
    return _nativeBridge.verifyAppPattern(pattern);
  }

  Future<bool> hasPattern() {
    return _nativeBridge.hasAppPattern();
  }

  Future<void> clearPattern() {
    return _nativeBridge.clearAppPattern();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../settings/settings_model.dart';
import '../settings/settings_repository.dart';
import 'app_lock_service.dart';
import 'pattern_input.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final SettingsRepository _settingsRepository = const SettingsRepository();
  final AppLockService _lockService = AppLockService();

  static const Duration _lockAfterBackground = Duration(seconds: 20);

  AppSettings _settings = AppSettings.defaults();
  bool _loading = true;
  bool _unlocked = false;
  bool _authInProgress = false;
  bool _biometricAvailable = false;
  bool _hasPattern = false;
  DateTime? _pausedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResume());
    }
  }

  bool get _canUseBiometric {
    return _settings.appLockEnabled &&
        _settings.biometricUnlockEnabled &&
        _biometricAvailable;
  }

  bool get _canUsePattern {
    return _settings.appLockEnabled &&
        _settings.patternUnlockEnabled &&
        _hasPattern;
  }

  bool get _hasUnlockMethod {
    return _canUseBiometric || _canUsePattern;
  }

  String get _storageSummaryText {
    final sender = _settings.rememberSenderEmail ? 'сохраняется' : 'не сохраняется';
    final recipient = _settings.rememberRecipientEmail ? 'сохраняется' : 'не сохраняется';
    final password = _settings.rememberPassword ? 'сохраняется' : 'не сохраняется';
    return 'Почта отправителя: $sender. '
        'Почта получателя: $recipient. '
        'Пароль приложения: $password.';
  }

  Future<void> _reloadSecurityConfig() async {
    _settings = await _settingsRepository.load();
    _biometricAvailable = await _lockService.canUseBiometric();
    _hasPattern = await _lockService.hasPattern();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _reloadSecurityConfig();
      if (!_settings.appLockEnabled) {
        _unlocked = true;
        return;
      }

      _unlocked = false;
      if (_canUseBiometric && !_canUsePattern) {
        await _authenticateBiometric(autoStarted: true);
      }
    } catch (error) {
      _error = 'Ошибка инициализации защиты: $error';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleResume() async {
    try {
      await _reloadSecurityConfig();
      if (!mounted) {
        return;
      }

      if (!_settings.appLockEnabled) {
        if (!_unlocked) {
          setState(() {
            _unlocked = true;
            _error = null;
          });
        }
        return;
      }

      if (!_unlocked) {
        return;
      }

      final pausedAt = _pausedAt;
      if (pausedAt == null) {
        return;
      }
      if (DateTime.now().difference(pausedAt) < _lockAfterBackground) {
        return;
      }

      setState(() {
        _unlocked = false;
        _error = null;
      });

      if (_canUseBiometric && !_canUsePattern) {
        unawaited(_authenticateBiometric(autoStarted: true));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Ошибка проверки защиты: $error';
      });
    }
  }

  Future<void> _authenticateBiometric({bool autoStarted = false}) async {
    if (_authInProgress || !_canUseBiometric) {
      return;
    }

    setState(() {
      _authInProgress = true;
      if (!autoStarted) {
        _error = null;
      }
    });

    final success = await _lockService.authenticateBiometric();
    if (!mounted) {
      return;
    }

    setState(() {
      _authInProgress = false;
      if (success) {
        _unlocked = true;
        _pausedAt = null;
      } else {
        _error = 'Биометрическая проверка не пройдена';
      }
    });
  }

  Future<void> _verifyPattern(List<int> points) async {
    if (_authInProgress || !_canUsePattern) {
      return;
    }

    if (points.length < 4) {
      setState(() {
        _error = 'Графический пароль должен содержать минимум 4 точки';
      });
      return;
    }

    setState(() {
      _authInProgress = true;
      _error = null;
    });

    final encodedPattern = points.join('-');
    final isValid = await _lockService.verifyPattern(encodedPattern);
    if (!mounted) {
      return;
    }

    setState(() {
      _authInProgress = false;
      if (isValid) {
        _unlocked = true;
        _pausedAt = null;
      } else {
        _error = 'Неверный графический пароль';
      }
    });
  }

  Future<void> _disableBrokenLock() async {
    try {
      final updated = _settings.copyWith(appLockEnabled: false);
      await _settingsRepository.save(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = updated;
        _unlocked = true;
      });
    } catch (error) {
      setState(() {
        _error = 'Не удалось отключить блокировку: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return widget.child;
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF72DBE9), Color(0xFF4798FD), Color(0xFF2E72F7)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF1550C4).withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/icons/app_icon.png',
                        width: 88,
                        height: 88,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Защищенный вход',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF16409E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _storageSummaryText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF2C4C93)),
                    ),
                    const SizedBox(height: 16),
                    if (_loading) ...<Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Проверяем параметры безопасности...'),
                    ] else ...<Widget>[
                      if (!_hasUnlockMethod) ...<Widget>[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Блокировка включена, но методы разблокировки не настроены.\nОтключите блокировку и включите биометрию или задайте графический пароль.',
                            style: TextStyle(color: Color(0xFF8B3E0E)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _disableBrokenLock,
                          icon: const Icon(Icons.warning_amber_outlined),
                          label: const Text('Отключить блокировку и продолжить'),
                        ),
                      ],
                      if (_canUseBiometric) ...<Widget>[
                        FilledButton.icon(
                          onPressed: _authInProgress
                              ? null
                              : () => _authenticateBiometric(),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Войти по отпечатку/биометрии'),
                        ),
                        if (_canUsePattern) const SizedBox(height: 10),
                      ],
                      if (_canUsePattern) ...<Widget>[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Нарисуйте графический пароль',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: PatternInput(
                            size: 280,
                            enabled: !_authInProgress,
                            onPatternCompleted: _verifyPattern,
                          ),
                        ),
                      ],
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFA22839)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


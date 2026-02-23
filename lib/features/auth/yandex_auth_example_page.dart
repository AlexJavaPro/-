import 'package:flutter/material.dart';

import 'models/yandex_auth_session.dart';
import 'yandex_auth_exception.dart';
import 'yandex_auth_repository.dart';
import 'widgets/yandex_login_button.dart';

class YandexAuthExamplePage extends StatefulWidget {
  const YandexAuthExamplePage({
    super.key,
    required this.repository,
  });

  final YandexAuthRepository repository;

  @override
  State<YandexAuthExamplePage> createState() => _YandexAuthExamplePageState();
}

class _YandexAuthExamplePageState extends State<YandexAuthExamplePage> {
  YandexAuthSession? _session;
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final saved = await widget.repository.readSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = saved;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _session = null;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final session = await widget.repository.signIn();
      if (!mounted) {
        return;
      }
      setState(() {
        _session = session;
      });
    } on YandexAuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Ошибка входа: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await widget.repository.clearSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _session?.user;
    final isAuthorized = user != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Yandex OAuth Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorText != null) ...[
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            if (isAuthorized) ...[
              Text('Идентификатор: ${user.identifier}'),
              Text('Email: ${user.bestEmail ?? 'не предоставлен'}'),
              Text('Login: ${user.login.isEmpty ? '-' : user.login}'),
              Text('ID: ${user.id.isEmpty ? '-' : user.id}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
              ),
            ] else
              YandexLoginButton(
                onPressed: _login,
                isLoading: _isLoading,
              ),
          ],
        ),
      ),
    );
  }
}

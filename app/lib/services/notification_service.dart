import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static final instance = NotificationService._();

  NotificationService._()
      : _debounce = const Duration(milliseconds: 500),
        _cooldown = const Duration(seconds: 5),
        _onSystemNotify = null;

  @visibleForTesting
  NotificationService.forTest({
    Duration debounce = Duration.zero,
    Duration cooldown = const Duration(seconds: 5),
    void Function(String title, String body)? onSystemNotify,
  })  : _debounce = debounce, // ignore: prefer_initializing_formals
        _cooldown = cooldown, // ignore: prefer_initializing_formals
        _onSystemNotify = onSystemNotify; // ignore: prefer_initializing_formals

  final Duration _debounce;
  final Duration _cooldown;
  final void Function(String title, String body)? _onSystemNotify;

  bool enabled = true;
  bool _isWindowFocused = true;
  void Function(String sessionLabel)? onToast;

  static final _promptRegex = RegExp(r'[\$#%❯>]\s*$');
  static final _ansiRegex = RegExp(
    r'(\x1B\][^\x07]*\x07|\x1B\][^\x1B]*\x1B\\|\x1B[@-Z\\-_]|\x1B\[[0-9;?]*[a-zA-Z~])',
  );

  final Map<String, Timer> _debounceTimers = {};
  final Map<String, DateTime> _lastNotified = {};

  static Future<void> init() async {
    await localNotifier.setup(appName: 'YourSSH');
  }

  void onWindowFocus() => _isWindowFocused = true;
  void onWindowBlur() => _isWindowFocused = false;

  void onTerminalData(
    String data, {
    required String sessionId,
    required String sessionLabel,
  }) {
    if (!enabled) return;
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers[sessionId] = Timer(
      _debounce,
      () => _checkPrompt(data, sessionId: sessionId, sessionLabel: sessionLabel),
    );
  }

  void _checkPrompt(
    String data, {
    required String sessionId,
    required String sessionLabel,
  }) {
    final stripped = data.replaceAll(_ansiRegex, '');
    final lastLine = stripped
        .trimRight()
        .split('\n')
        .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (!_promptRegex.hasMatch(lastLine)) return;

    final now = DateTime.now();
    final last = _lastNotified[sessionId];
    if (last != null && now.difference(last) < _cooldown) return;
    _lastNotified[sessionId] = now;

    if (_isWindowFocused) {
      onToast?.call(sessionLabel);
    } else {
      _dispatchSystem('YourSSH — Command finished', sessionLabel);
    }
  }

  void _dispatchSystem(String title, String body) {
    final notify = _onSystemNotify;
    if (notify != null) {
      notify(title, body);
    } else {
      LocalNotification(title: title, body: body).show();
    }
  }

  void removeSession(String sessionId) {
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers.remove(sessionId);
    _lastNotified.remove(sessionId);
  }

  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _lastNotified.clear();
  }
}

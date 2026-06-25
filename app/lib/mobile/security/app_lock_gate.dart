import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

const String kAppLockPrefKey = 'app_lock_enabled';

/// Wraps the mobile app in a biometric lock. Locked on launch (and on
/// resume-from-background) when enabled; unlocks on a successful auth. The
/// [authenticator] and [enabledOverride] seams keep the state machine testable
/// without real device biometrics.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? authenticator;
  final bool? enabledOverride;

  const AppLockGate({
    super.key,
    required this.child,
    this.authenticator,
    this.enabledOverride,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    final enabled = widget.enabledOverride ??
        (await SharedPreferences.getInstance()).getBool(kAppLockPrefKey) ??
        true;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
    });
    if (enabled) _authenticate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    // Don't disturb the lock state while our own biometric prompt is up — it
    // briefly drives the app through inactive/paused → resumed, which would
    // otherwise re-lock and re-prompt in a loop right after a successful unlock.
    if (_authInFlight) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Cover the app-switcher snapshot: lock before the OS captures it.
        if (!_locked && mounted) setState(() => _locked = true);
      case AppLifecycleState.resumed:
        if (_locked) _authenticate();
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<bool> _defaultAuth() async {
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: 'Unlock YourSSH',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _authenticate() async {
    if (_authInFlight) return;
    _authInFlight = true;
    final ok = await (widget.authenticator ?? _defaultAuth)();
    if (mounted && ok) setState(() => _locked = false);
    // Clear the guard one frame later, so the inactive→resumed transition that
    // accompanies dismissing the system biometric sheet is still ignored above
    // (otherwise it re-locks immediately after unlocking).
    WidgetsBinding.instance.addPostFrameCallback((_) => _authInFlight = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text('YourSSH is locked',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _authenticate, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}

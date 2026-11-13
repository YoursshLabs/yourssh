import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/sync_provider.dart';
import '../../widgets/terminal_appearance_controls.dart';
import '../security/app_lock_gate.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../util/mobile_prefs.dart';
import '../widgets/list_group.dart';
import '../widgets/mobile_card.dart';
import '../widgets/settings_row.dart';
import 'mobile_sync_screen.dart';

/// Settings tab — grouped preferences and security.
/// Groups: TERMINAL · SECURITY · KEYBOARD & SYNC
/// Both "Supabase sync" and "Pair new device" push [MobileSyncScreen].
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  // ── Security ──────────────────────────────────────────────────────────────
  bool _appLock = true;

  // ── Keyboard ──────────────────────────────────────────────────────────────
  bool _accessoryBar = true;

  // ── Version ───────────────────────────────────────────────────────────────
  String _version = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _appLock      = p.getBool(kAppLockPrefKey)      ?? true;
          _accessoryBar = p.getBool(kAccessoryBarPrefKey) ?? true;
        });
      }
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // FHeader adds the top safe area itself.
          const FHeader(title: Text('Settings')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                top: MobileTokens.space4,
                left: MobileTokens.space4,
                right: MobileTokens.space4,
                bottom: MobileTokens.space5,
              ),
              children: [
                _syncBanner(sync),
                const SizedBox(height: MobileTokens.space5),
                _terminalGroup(),
                const SizedBox(height: MobileTokens.space5),
                _securityGroup(),
                const SizedBox(height: MobileTokens.space5),
                _keyboardSyncGroup(sync),
                const SizedBox(height: MobileTokens.space5),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sync banner ───────────────────────────────────────────────────────────

  Widget _syncBanner(SyncProvider sync) {
    final active = sync.isSupabaseConfigured;
    return MobileCard(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'Sync active' : 'Sync off',
                  style: mobileBody(
                    size: 14,
                    weight: FontWeight.w600,
                    color: active ? MobileColors.textPrimary : MobileColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Supabase · end-to-end encrypted',
                  style: mobileBody(size: 12, color: MobileColors.textMuted),
                ),
              ],
            ),
          ),
          FBadge(
            variant: active ? FBadgeVariant.primary : FBadgeVariant.secondary,
            child: Text(active ? 'On' : 'Off'),
          ),
        ],
      ),
    );
  }

  // ── TERMINAL group ────────────────────────────────────────────────────────

  Widget _terminalGroup() {
    return ListGroup(
      label: 'Terminal',
      children: [
        Padding(
          padding: const EdgeInsets.all(MobileTokens.space4),
          child: const TerminalAppearanceControls(
            layout: AppearanceControlsLayout.rows,
          ),
        ),
      ],
    );
  }

  // ── SECURITY group ────────────────────────────────────────────────────────

  Widget _securityGroup() {
    return ListGroup(
      label: 'Security',
      children: [
        SettingsRow(
          leading: Icon(FLucideIcons.fingerprintPattern, color: MobileColors.textMuted, size: 20),
          title: 'Biometric unlock',
          toggle: _appLock,
          onToggle: (v) async {
            setState(() => _appLock = v);
            final p = await SharedPreferences.getInstance();
            await p.setBool(kAppLockPrefKey, v);
          },
        ),
        SettingsRow(
          leading: const Icon(FLucideIcons.timer, color: MobileColors.textMuted, size: 20),
          title: 'Auto-lock',
          value: 'Immediately when you leave the app',
        ),
      ],
    );
  }

  // ── KEYBOARD & SYNC group ─────────────────────────────────────────────────

  Widget _keyboardSyncGroup(SyncProvider sync) {
    return ListGroup(
      label: 'Keyboard & Sync',
      children: [
        SettingsRow(
          leading: Icon(FLucideIcons.keyboard, color: MobileColors.textMuted, size: 20),
          title: 'Shortcut key bar',
          toggle: _accessoryBar,
          onToggle: (v) async {
            setState(() => _accessoryBar = v);
            final p = await SharedPreferences.getInstance();
            await p.setBool(kAccessoryBarPrefKey, v);
          },
        ),
        SettingsRow(
          leading: Icon(FLucideIcons.cloudUpload, color: MobileColors.textMuted, size: 20),
          title: 'Supabase sync',
          value: sync.isSupabaseConfigured ? 'Configured' : null,
          onTap: _pushSyncScreen,
        ),
        SettingsRow(
          leading: Icon(FLucideIcons.scanQrCode, color: MobileColors.textMuted, size: 20),
          title: 'Pair new device',
          onTap: _pushSyncScreen,
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _footer() {
    return Center(
      child: Text(
        'YourSSH · Version $_version',
        style: mobileBody(size: 12, color: MobileColors.textFaint),
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _pushSyncScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const MobileSyncScreen()),
    );
  }
}

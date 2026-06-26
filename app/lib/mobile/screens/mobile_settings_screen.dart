import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/terminal_appearance_controls.dart';
import '../security/app_lock_gate.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../util/mobile_prefs.dart';
import '../widgets/list_group.dart';
import '../widgets/settings_row.dart';
import 'mobile_qr_scan_screen.dart';

/// Settings tab — grouped preferences and security.
/// Groups: TERMINAL · SECURITY · KEYBOARD & SYNC
/// Sync functionality (Supabase config + P2P QR import) is preserved via
/// inline bottom sheets (Task 16 will replace with MobileSyncScreen).
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  // ── Sync form state ───────────────────────────────────────────────────────
  final _url  = TextEditingController();
  final _anon = TextEditingController();
  final _code = TextEditingController();
  bool _dirty   = false;
  bool _pulling = false;

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

  @override
  void dispose() {
    _url.dispose();
    _anon.dispose();
    _code.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    // Mirror the provider until the user edits a field.
    if (!_dirty) {
      if (_url.text  != sync.supabaseUrl)    _url.text  = sync.supabaseUrl;
      if (_anon.text != sync.supabaseAnonKey) _anon.text = sync.supabaseAnonKey;
      if (_code.text != sync.syncCode)        _code.text = sync.syncCode;
    }

    return Scaffold(
      backgroundColor: MobileColors.bg,
      appBar: AppBar(
        backgroundColor: MobileColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Settings', style: mobileHeading()),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: MobileColors.textMuted, size: 22),
            onPressed: null, // placeholder — Task 16
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
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
    );
  }

  // ── Sync banner ───────────────────────────────────────────────────────────

  Widget _syncBanner(SyncProvider sync) {
    final active = sync.isSupabaseConfigured;
    return Container(
      decoration: BoxDecoration(
        color: MobileColors.surface,
        borderRadius: BorderRadius.circular(MobileTokens.radiusCard),
        border: Border.all(color: MobileColors.border),
      ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? MobileColors.accent.withAlpha(38)
                  : MobileColors.border,
              borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
            ),
            child: Text(
              active ? 'On' : 'Off',
              style: mobileBody(
                size: 12,
                weight: FontWeight.w600,
                color: active ? MobileColors.accent : MobileColors.textFaint,
              ),
            ),
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
          leading: Icon(Icons.fingerprint, color: MobileColors.textMuted, size: 20),
          title: 'Biometric unlock',
          toggle: _appLock,
          onToggle: (v) async {
            setState(() => _appLock = v);
            final p = await SharedPreferences.getInstance();
            await p.setBool(kAppLockPrefKey, v);
          },
        ),
        SettingsRow(
          leading: Icon(Icons.lock_clock_outlined, color: MobileColors.textMuted, size: 20),
          title: 'Auto-lock',
          value: 'After 1 min',
          onTap: () {}, // placeholder — future enhancement
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
          leading: Icon(Icons.keyboard_outlined, color: MobileColors.textMuted, size: 20),
          title: 'Shortcut key bar',
          toggle: _accessoryBar,
          onToggle: (v) async {
            setState(() => _accessoryBar = v);
            final p = await SharedPreferences.getInstance();
            await p.setBool(kAccessoryBarPrefKey, v);
          },
        ),
        SettingsRow(
          leading: Icon(Icons.cloud_sync_outlined, color: MobileColors.textMuted, size: 20),
          title: 'Supabase sync',
          value: sync.isSupabaseConfigured ? 'Configured' : null,
          onTap: () => _showSupabaseSyncSheet(sync),
        ),
        SettingsRow(
          leading: Icon(Icons.qr_code_scanner, color: MobileColors.textMuted, size: 20),
          title: 'Pair new device',
          onTap: _scanQr,
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

  // ── Supabase sync sheet (preserved from original) ─────────────────────────

  void _showSupabaseSyncSheet(SyncProvider sync) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => _SupabaseSyncSheet(
          urlController: _url,
          anonController: _anon,
          codeController: _code,
          pulling: _pulling,
          onDirty: () => _dirty = true,
          onSave: () async {
            await _save();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          onPull: () async {
            setSheetState(() => _pulling = true);
            await _pull();
            if (ctx.mounted) {
              setSheetState(() => _pulling = false);
              Navigator.of(ctx).pop();
            }
          },
        ),
      ),
    );
  }

  // ── P2P QR scan (preserved from original) ────────────────────────────────

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MobileQrScanScreen()),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  // ── Save / pull helpers (unchanged logic) ────────────────────────────────

  Future<void> _save() async {
    final sync = context.read<SyncProvider>();
    await sync.setSupabaseConfig(_url.text, _anon.text);
    await sync.setSyncCode(_code.text);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sync settings saved')));
    }
  }

  Future<void> _pull() async {
    final payload = await context.read<SyncService>().pull();
    if (!mounted) return;
    if (payload != null) {
      await context
          .read<HostProvider>()
          .replaceAll(payload.hosts, payload.passwords);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported ${payload.hosts.length} hosts from cloud'),
        ));
      }
    } else if (mounted) {
      final err = context.read<SyncProvider>().error;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err ?? 'Nothing new to pull')));
    }
  }
}

// ── Supabase sync bottom sheet ────────────────────────────────────────────────

class _SupabaseSyncSheet extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController anonController;
  final TextEditingController codeController;
  final bool pulling;
  final VoidCallback onDirty;
  final VoidCallback onSave;
  final VoidCallback onPull;

  const _SupabaseSyncSheet({
    required this.urlController,
    required this.anonController,
    required this.codeController,
    required this.pulling,
    required this.onDirty,
    required this.onSave,
    required this.onPull,
  });

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: MobileTokens.space4,
        right: MobileTokens.space4,
        top: MobileTokens.space4,
        bottom: MobileTokens.space4 + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: MobileTokens.space4),
              decoration: BoxDecoration(
                color: MobileColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Supabase Sync', style: mobileHeading()),
          const SizedBox(height: MobileTokens.space2),
          Text(
            'Pull hosts from your desktop via Supabase.',
            style: mobileBody(size: 13, color: MobileColors.textMuted),
          ),
          const SizedBox(height: MobileTokens.space4),
          _field(context, urlController, 'Supabase URL', 'sync-url'),
          _field(context, anonController, 'Anon key', 'sync-anon'),
          _field(context, codeController, 'Sync code (12 chars)', 'sync-code'),
          const SizedBox(height: MobileTokens.space3),
          Row(
            children: [
              FilledButton(onPressed: onSave, child: const Text('Save')),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: pulling ? null : onPull,
                child: pulling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pull from cloud'),
              ),
            ],
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 10),
            Text(
              sync.error!,
              style: mobileBody(size: 12, color: AppColors.red),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(BuildContext context, TextEditingController c, String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MobileTokens.space3),
      child: TextField(
        key: Key(key),
        controller: c,
        onChanged: (_) => onDirty(),
        style: const TextStyle(color: MobileColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

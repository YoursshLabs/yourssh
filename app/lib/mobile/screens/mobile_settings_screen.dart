import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/terminal_appearance_controls.dart';
import '../security/app_lock_gate.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/mobile_card.dart';
import '../widgets/section_header.dart';
import 'mobile_qr_scan_screen.dart';

/// Settings tab. M3 ships the Sync section (cloud pull + P2P QR scan).
/// Appearance + app-lock arrive in M5.
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  final _url = TextEditingController();
  final _anon = TextEditingController();
  final _code = TextEditingController();
  // Once the user edits a field we stop syncing it from the provider, so an
  // async config load that completes after the first build can't clobber typing.
  bool _dirty = false;
  bool _pulling = false;
  bool _appLock = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => _appLock = p.getBool(kAppLockPrefKey) ?? true);
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _anon.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    if (!_dirty) {
      // Mirror the provider until the user edits a field. SyncProvider loads its
      // values asynchronously, so this re-seeds once the load completes instead
      // of latching empty on the first frame (which a Save would then persist).
      if (_url.text != sync.supabaseUrl) _url.text = sync.supabaseUrl;
      if (_anon.text != sync.supabaseAnonKey) _anon.text = sync.supabaseAnonKey;
      if (_code.text != sync.syncCode) _code.text = sync.syncCode;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar:
          AppBar(backgroundColor: AppColors.bg, title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader('Cloud sync'),
            MobileCard(
              padding: const EdgeInsets.all(MobileTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pull hosts from your desktop via Supabase.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: MobileTokens.space3),
                  _field(_url, 'Supabase URL', 'sync-url'),
                  _field(_anon, 'Anon key', 'sync-anon'),
                  _field(_code, 'Sync code (12 chars)', 'sync-code'),
                  const SizedBox(height: MobileTokens.space2),
                  Row(
                    children: [
                      FilledButton(onPressed: _save, child: const Text('Save')),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _pulling ? null : _pull,
                        child: _pulling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Pull from cloud'),
                      ),
                    ],
                  ),
                  if (sync.error != null) ...[
                    const SizedBox(height: 10),
                    Text(sync.error!,
                        style: const TextStyle(color: AppColors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
            const SectionHeader('P2P transfer'),
            MobileCard(
              padding: const EdgeInsets.all(MobileTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Scan the QR code shown on your desktop (Settings → Sync → Show QR).',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: MobileTokens.space3),
                  FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                    onPressed: _scan,
                  ),
                ],
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
            const SectionHeader('Security'),
            MobileCard(
              padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2),
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _appLock,
                  onChanged: (v) async {
                    setState(() => _appLock = v);
                    final p = await SharedPreferences.getInstance();
                    await p.setBool(kAppLockPrefKey, v);
                  },
                  title: const Text('Require biometrics to open',
                      style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: const Text('Applies on next app launch',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
            const SectionHeader('Terminal appearance'),
            MobileCard(
              padding: const EdgeInsets.all(MobileTokens.space3),
              child: const TerminalAppearanceControls(
                  layout: AppearanceControlsLayout.rows),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MobileQrScanScreen()),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

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
    setState(() => _pulling = true);
    final payload = await context.read<SyncService>().pull();
    if (!mounted) return;
    if (payload != null) {
      await context
          .read<HostProvider>()
          .replaceAll(payload.hosts, payload.passwords);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Imported ${payload.hosts.length} hosts from cloud')));
      }
    } else if (mounted) {
      final err = context.read<SyncProvider>().error;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err ?? 'Nothing new to pull')));
    }
    if (mounted) setState(() => _pulling = false);
  }

  Widget _field(TextEditingController c, String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: Key(key),
        controller: c,
        onChanged: (_) => _dirty = true,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

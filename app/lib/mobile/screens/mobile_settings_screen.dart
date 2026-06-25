import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
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
  bool _seeded = false;
  bool _pulling = false;

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
    if (!_seeded) {
      _url.text = sync.supabaseUrl;
      _anon.text = sync.supabaseAnonKey;
      _code.text = sync.syncCode;
      _seeded = true;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar:
          AppBar(backgroundColor: AppColors.bg, title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Cloud Sync',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Pull hosts from your desktop via Supabase.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            _field(_url, 'Supabase URL', 'sync-url'),
            _field(_anon, 'Anon key', 'sync-anon'),
            _field(_code, 'Sync code (12 chars)', 'sync-code'),
            const SizedBox(height: 8),
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
            const SizedBox(height: 24),
            const Text('P2P transfer',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
                'Scan the QR code shown on your desktop (Settings → Sync → Show QR).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
              onPressed: _scan,
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
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

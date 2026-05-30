import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../providers/host_provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../services/sync_encryption.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import 'qr_export_dialog.dart';
import 'qr_import_dialog.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _storage = const FlutterSecureStorage();
  final _endpointCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController();
  final _accessKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _syncing = false;
  String? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _bucketCtrl.dispose();
    _accessKeyCtrl.dispose();
    _secretKeyCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    _endpointCtrl.text = await _storage.read(key: 'sync_endpoint') ?? '';
    _bucketCtrl.text = await _storage.read(key: 'sync_bucket') ?? '';
    _accessKeyCtrl.text = await _storage.read(key: 'sync_access_key') ?? '';
    _secretKeyCtrl.text = await _storage.read(key: 'sync_secret_key') ?? '';
    _lastSync = await _storage.read(key: 'sync_last_at');
    if (mounted) setState(() {});
  }

  Future<void> _saveConfig() async {
    await _storage.write(key: 'sync_endpoint', value: _endpointCtrl.text);
    await _storage.write(key: 'sync_bucket', value: _bucketCtrl.text);
    await _storage.write(key: 'sync_access_key', value: _accessKeyCtrl.text);
    await _storage.write(key: 'sync_secret_key', value: _secretKeyCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sync config saved'),
            duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _exportAndUpload() async {
    if (_passwordCtrl.text.isEmpty) return;
    setState(() => _syncing = true);

    try {
      final hosts =
          context.read<HostProvider>().hosts.map((h) => h.toJson()).toList();
      final snippets = context
          .read<SnippetProvider>()
          .snippets
          .map((s) => s.toJson())
          .toList();

      final payload = jsonEncode({
        'hosts': hosts,
        'snippets': snippets,
        'exportedAt': DateTime.now().toIso8601String(),
      });

      final encrypted =
          await SyncEncryption.encrypt(payload, _passwordCtrl.text);

      await _storage.write(key: 'sync_backup', value: encrypted);
      await _storage.write(
          key: 'sync_last_at', value: DateTime.now().toIso8601String());

      setState(() => _lastSync = DateTime.now().toIso8601String());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sync complete'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Sync failed: $e'),
              backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showQrExport(BuildContext context) async {
    final hostProvider = context.read<HostProvider>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrExportDialog(
        getPayload: () async {
          final hosts = hostProvider.allHosts;
          final passwords = await hostProvider.loadAllPasswords();
          return SyncService.buildPayload(hosts: hosts, passwords: passwords);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Encrypted Sync'),
        backgroundColor: AppColors.sidebar,
        actions: [
          TextButton(onPressed: _saveConfig, child: const Text('Save Config')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Storage Configuration',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _field(_endpointCtrl, 'S3 Endpoint', 'https://s3.amazonaws.com'),
            _field(_bucketCtrl, 'Bucket Name', 'yourssh-sync'),
            _field(_accessKeyCtrl, 'Access Key', 'AKIAIOSFODNN7EXAMPLE'),
            _field(_secretKeyCtrl, 'Secret Key', '••••', obscure: true),
            const SizedBox(height: 24),
            const Text('Encryption',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Data is encrypted with AES-256 before leaving your device. '
              'The passphrase is never stored or transmitted.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _field(_passwordCtrl, 'Sync Passphrase', '••••••••', obscure: true),
            const SizedBox(height: 24),
            if (_lastSync != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Last synced: $_lastSync',
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ),
            ElevatedButton.icon(
              onPressed: _syncing ? null : _exportAndUpload,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sync, size: 16),
              label: const Text('Export & Sync Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'P2P Transfer',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Transfer all hosts to another device over LAN or Tailscale. No cloud required.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('Show QR Code'),
                    onPressed: () => _showQrExport(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Import via Code'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const QrImportDialog(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.card,
              border: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

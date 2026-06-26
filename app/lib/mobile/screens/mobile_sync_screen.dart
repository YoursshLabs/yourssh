import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/p2p_sync_encryption.dart';
import '../../services/p2p_sync_service.dart';
import '../../services/sync_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/mobile_card.dart';
import '../widgets/section_header.dart';
import 'mobile_qr_scan_screen.dart';

/// Screen 09 — Sync / QR pairing.
///
/// Shows:
/// - Heading + body copy about end-to-end encryption.
/// - QR card: starts a P2P server and renders the transfer code as a QR.
/// - Caption below QR.
/// - Supabase status card with an E2E badge.
/// - "Scan QR code" button → [MobileQrScanScreen].
class MobileSyncScreen extends StatefulWidget {
  const MobileSyncScreen({super.key});

  @override
  State<MobileSyncScreen> createState() => _MobileSyncScreenState();
}

class _MobileSyncScreenState extends State<MobileSyncScreen> {
  final _p2p = P2PSyncService();
  String? _qrData;
  String _qrStatus = 'Starting…';
  int _secondsLeft = 120;
  Timer? _countdown;

  // ── Supabase config form state ────────────────────────────────────────────
  final _url  = TextEditingController();
  final _anon = TextEditingController();
  final _code = TextEditingController();
  bool _editingConfig = false;
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _p2p.stop();
    _url.dispose();
    _anon.dispose();
    _code.dispose();
    super.dispose();
  }

  // ── Supabase config helpers ───────────────────────────────────────────────

  void _prefillConfig() {
    final sync = context.read<SyncProvider>();
    _url.text  = sync.supabaseUrl;
    _anon.text = sync.supabaseAnonKey;
    _code.text = sync.syncCode;
  }

  Future<void> _saveConfig() async {
    final sync = context.read<SyncProvider>();
    await sync.setSupabaseConfig(_url.text, _anon.text);
    await sync.setSyncCode(_code.text);
    if (mounted) {
      setState(() => _editingConfig = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync settings saved')),
      );
    }
  }

  Future<void> _pullFromCloud() async {
    setState(() => _pulling = true);
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Nothing new to pull')),
        );
      }
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  // ── P2P server / QR build ─────────────────────────────────────────────────

  Future<void> _startServer() async {
    setState(() {
      _qrData = null;
      _qrStatus = 'Preparing…';
    });
    _countdown?.cancel();

    try {
      final ifaces = await _p2p.getLocalInterfaces();
      if (!mounted) return;
      if (ifaces.isEmpty) {
        setState(() => _qrStatus = 'No network interface found');
        return;
      }

      final hostProvider = context.read<HostProvider>();
      final hosts = hostProvider.allHosts;
      final passwords = await hostProvider.loadAllPasswords();
      final payload = SyncService.buildPayload(hosts: hosts, passwords: passwords);
      if (!mounted) return;

      final key = P2PSyncEncryption.generateKey();
      final encrypted = await P2PSyncEncryption.encrypt(payload, key);
      final url = await _p2p.startServer(
        encryptedPayload: encrypted,
        hostAddress: ifaces.first.address,
      );
      final qrJson = jsonEncode({'u': url, 'k': base64.encode(key)});

      _secondsLeft = 120;
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_secondsLeft <= 0) {
          t.cancel();
          _p2p.stop();
          if (mounted) setState(() => _qrStatus = 'Code expired — tap Refresh');
          return;
        }
        setState(() => _secondsLeft--);
      });

      _p2p.onServerError = (e) {
        if (mounted) setState(() => _qrStatus = 'Transfer error: $e');
      };

      if (mounted) setState(() => _qrData = qrJson);
    } catch (e) {
      if (mounted) setState(() => _qrStatus = 'Error: $e');
    }
  }

  // ── Format helpers ────────────────────────────────────────────────────────

  String get _countdownText {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatLastSync(DateTime? t) {
    if (t == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    return Scaffold(
      backgroundColor: MobileColors.bg,
      appBar: _buildAppBar(),
      body: ListView(
        padding: EdgeInsets.only(
          top: MobileTokens.space4,
          left: MobileTokens.space4,
          right: MobileTokens.space4,
          bottom: MobileTokens.space5,
        ),
        children: [
          _buildHero(),
          const SizedBox(height: MobileTokens.space5),
          _buildQrSection(),
          const SizedBox(height: MobileTokens.space5),
          _buildStatusSection(sync),
          const SizedBox(height: MobileTokens.space5),
          _buildConfigSection(sync),
          const SizedBox(height: MobileTokens.space5),
          _buildScanButton(),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  AppBar _buildAppBar() => AppBar(
        backgroundColor: MobileColors.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          color: MobileColors.accent,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Settings',
        ),
        title: Text('Pair device', style: mobileHeading()),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            color: MobileColors.textMuted,
            onPressed: null, // placeholder
          ),
        ],
      );

  // ── Hero copy ─────────────────────────────────────────────────────────────

  Widget _buildHero() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sync with Supabase', style: mobileHeading(size: 22)),
          const SizedBox(height: MobileTokens.space2),
          Text(
            'No account needed. Your hosts, keys & snippets stay end-to-end '
            'encrypted across devices.',
            style: mobileBody(size: 14, color: MobileColors.textMuted),
          ),
        ],
      );

  // ── QR section ────────────────────────────────────────────────────────────

  Widget _buildQrSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader('Pair a new device'),
          MobileCard(
            padding: const EdgeInsets.all(MobileTokens.space5),
            child: Column(
              children: [
                _buildQrContent(),
                const SizedBox(height: MobileTokens.space3),
                Text(
                  'Open YourSSH on another device and scan this',
                  style: mobileBody(size: 13, color: MobileColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildQrContent() {
    if (_qrData != null) {
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(MobileTokens.radiusCard),
            ),
            padding: const EdgeInsets.all(MobileTokens.space3),
            child: QrImageView(
              data: _qrData!,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: MobileTokens.space2),
          Text(
            _countdownText,
            style: mobileBody(
              size: 20,
              weight: FontWeight.w700,
              color: MobileColors.textPrimary,
            ),
          ),
        ],
      );
    }

    // Loading / error state
    return SizedBox(
      height: 240,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_qrStatus.startsWith('Error') || _qrStatus.contains('expired'))
            Column(
              children: [
                Icon(Icons.error_outline, color: MobileColors.textMuted, size: 40),
                const SizedBox(height: MobileTokens.space3),
                Text(
                  _qrStatus,
                  style: mobileBody(size: 13, color: MobileColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: MobileTokens.space3),
                FilledButton(
                  onPressed: _startServer,
                  child: const Text('Refresh'),
                ),
              ],
            )
          else
            Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: MobileTokens.space3),
                Text(
                  _qrStatus,
                  style: mobileBody(size: 13, color: MobileColors.textMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Status section ────────────────────────────────────────────────────────

  Widget _buildStatusSection(SyncProvider sync) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader('Cloud sync'),
          MobileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sync.isSupabaseConfigured
                                ? 'Supabase connected'
                                : 'Supabase not configured',
                            style: mobileBody(
                              size: 14,
                              weight: FontWeight.w600,
                              color: sync.isSupabaseConfigured
                                  ? MobileColors.textPrimary
                                  : MobileColors.textMuted,
                            ),
                          ),
                          if (sync.isSupabaseConfigured) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Last sync · ${_formatLastSync(sync.lastSynced)}',
                              style: mobileBody(
                                size: 12,
                                color: MobileColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (sync.isSupabaseConfigured)
                      _E2EBadge(),
                  ],
                ),
                if (sync.isSupabaseConfigured) ...[
                  const SizedBox(height: MobileTokens.space3),
                  _SyncStatusRow(status: sync.status),
                ],
              ],
            ),
          ),
        ],
      );

  // ── Supabase config section ───────────────────────────────────────────────

  Widget _buildConfigSection(SyncProvider sync) {
    final isConfigured = sync.isSupabaseConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Supabase credentials'),
        if (!isConfigured || _editingConfig)
          _buildConfigForm(sync)
        else
          MobileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'URL: ${sync.supabaseUrl}',
                  style: mobileBody(size: 12, color: MobileColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: MobileTokens.space2),
                OutlinedButton(
                  onPressed: () {
                    _prefillConfig();
                    setState(() => _editingConfig = true);
                  },
                  child: const Text('Edit credentials'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConfigForm(SyncProvider sync) => MobileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your Supabase project URL, anon key, and 12-character sync code.',
              style: mobileBody(size: 13, color: MobileColors.textMuted),
            ),
            const SizedBox(height: MobileTokens.space3),
            _configField(_url, 'Supabase URL', 'sync-url'),
            _configField(_anon, 'Anon key', 'sync-anon'),
            _configField(_code, 'Sync code (12 chars)', 'sync-code'),
            const SizedBox(height: MobileTokens.space3),
            Row(
              children: [
                FilledButton(
                  onPressed: _saveConfig,
                  child: const Text('Save'),
                ),
                const SizedBox(width: MobileTokens.space3),
                OutlinedButton(
                  onPressed: _pulling ? null : _pullFromCloud,
                  child: _pulling
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
              const SizedBox(height: MobileTokens.space2),
              Text(
                sync.error!,
                style: mobileBody(size: 12, color: MobileColors.red),
              ),
            ],
          ],
        ),
      );

  Widget _configField(
    TextEditingController controller,
    String label,
    String key,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: MobileTokens.space3),
        child: TextField(
          key: Key(key),
          controller: controller,
          style: const TextStyle(
            color: MobileColors.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(labelText: label),
        ),
      );

  // ── Scan button ───────────────────────────────────────────────────────────

  Widget _buildScanButton() => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text('Scan QR code'),
          style: FilledButton.styleFrom(
            backgroundColor: MobileColors.accent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: MobileTokens.space4),
            textStyle: mobileBody(
              size: 16,
              weight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          onPressed: () async {
            final result = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const MobileQrScanScreen()),
            );
            if (result != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result)),
              );
            }
          },
        ),
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _E2EBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: MobileColors.green.withAlpha(38),
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: Border.all(color: MobileColors.green.withAlpha(76)),
      ),
      child: Text(
        'E2E',
        style: mobileBody(
          size: 11,
          weight: FontWeight.w700,
          color: MobileColors.green,
        ),
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final SyncStatus status;
  const _SyncStatusRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SyncStatus.synced  => ('Synced', MobileColors.green),
      SyncStatus.syncing => ('Syncing…', MobileColors.yellow),
      SyncStatus.error   => ('Sync error', MobileColors.red),
      SyncStatus.idle    => ('Idle', MobileColors.textMuted),
    };

    return Row(
      children: [
        Container(
          width: MobileTokens.statusDot,
          height: MobileTokens.statusDot,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: MobileTokens.space2),
        Text(label, style: mobileBody(size: 12, color: color)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/sync_code.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../qr_export_dialog.dart';
import '../qr_import_dialog.dart';
import 'settings_tiles.dart';

enum _SyncMode { cloud, p2p }

/// Settings → Sync: Supabase cloud sync (backend, sync code, status) and the
/// one-shot P2P transfer over LAN.
class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  State<SyncSettingsSection> createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  final _urlController = TextEditingController();
  final _anonKeyController = TextEditingController();
  final _syncCodeController = TextEditingController();
  bool _showAnonKey = false;
  bool _showSyncCode = false;
  bool _urlHasText = false;
  bool _testing = false;
  bool _testOk = false;
  String? _testError;
  bool _needsServiceKey = false;
  _SyncMode _syncMode = _SyncMode.cloud;

  /// The backend fields were filled from the provider once; later provider
  /// changes never overwrite what the user typed.
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(() {
      final has = _urlController.text.isNotEmpty;
      if (has != _urlHasText) setState(() => _urlHasText = has);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs after initState and on every SyncProvider change (watched in
    // build), so a provider that finishes loading after the first frame
    // still fills the fields.
    final sync = context.read<SyncProvider>();
    if (!_hydrated && sync.isSupabaseConfigured) {
      _hydrated = true;
      if (_urlController.text.isEmpty) _urlController.text = sync.supabaseUrl;
      if (_anonKeyController.text.isEmpty) {
        _anonKeyController.text = sync.supabaseAnonKey;
      }
      _urlHasText = _urlController.text.isNotEmpty;
      _testOk = true;
    }
    if (SyncCode.normalize(_syncCodeController.text) != sync.syncCode) {
      _syncCodeController.text = SyncCode.format(sync.syncCode);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _anonKeyController.dispose();
    _syncCodeController.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    final code = await context.read<SyncProvider>().generateSyncCode();
    if (!mounted) return;
    setState(() => _syncCodeController.text = SyncCode.format(code));
    await _pushNow();
  }

  Future<void> _saveCode() async {
    if (!SyncCode.isValid(_syncCodeController.text)) {
      AppSnack.error(context, 'Enter a valid 12-character sync code.');
      return;
    }
    final provider = context.read<SyncProvider>();
    await provider.setSyncCode(_syncCodeController.text);
    if (!mounted) return;
    setState(
      () => _syncCodeController.text = SyncCode.format(provider.syncCode),
    );
    await _pushNow();
  }

  Future<void> _regenerate() async {
    final ok = await showYsConfirm(
      context,
      title: 'Regenerate sync code?',
      message:
          'A new code creates a new cloud record. Data tied to the old code '
          'becomes unreachable until you re-enter the old code.',
      confirmLabel: 'Regenerate',
      destructive: true,
    );
    if (ok) await _generateCode();
  }

  Future<void> _pushNow() async {
    final sync = context.read<SyncProvider>();
    if (!sync.enabled || !sync.isSupabaseConfigured) return;
    final syncService = context.read<SyncService>();
    final hostProvider = context.read<HostProvider>();
    await syncService.push(
      hosts: hostProvider.allHosts,
      loadPasswords: hostProvider.loadAllPasswords,
    );
    syncService.restartRetryTimer();
  }

  Future<void> _testAndSave() async {
    final url = _urlController.text.trim();
    final anonKey = _anonKeyController.text.trim();
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() {
        _testError = 'URL and Anon key are required';
        _testOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testError = null;
      _testOk = false;
      _needsServiceKey = false;
    });
    try {
      final svc = SupabaseService(url, anonKey, '');
      final (outcome, error) = await svc.testConnection();
      if (!mounted) return;

      if (outcome == TestConnectionOutcome.connected) {
        _hydrated = true;
        await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
        if (!mounted) return;
        await _pushNow();
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testOk = true;
        });
        return;
      }

      if (outcome == TestConnectionOutcome.tableNotFound) {
        setState(() {
          _testing = false;
          _needsServiceKey = true;
        });
        return;
      }

      setState(() {
        _testing = false;
        _testError = error ?? 'Connection failed';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testError = e.toString();
      });
    }
  }

  Future<void> _disconnect() async {
    await context.read<SyncProvider>().clearSupabaseConfig();
    if (!mounted) return;
    setState(() {
      _testOk = false;
      _urlController.clear();
      _anonKeyController.clear();
    });
  }

  Future<void> _showQrExport(BuildContext context) async {
    final hostProvider = context.read<HostProvider>();
    await showYsDialog<void>(
      context,
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
    final sync = context.watch<SyncProvider>();
    return SettingsSection(
      title: 'Sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FTabs(
            key: const ValueKey('sync-mode-tabs'),
            control: .lifted(
              index: _syncMode.index,
              onChange: (i) => setState(() => _syncMode = _SyncMode.values[i]),
            ),
            children: [
              _modeTab('Cloud Sync', FLucideIcons.cloud),
              _modeTab('P2P Transfer', FLucideIcons.radioTower),
            ],
          ),
          settingsTileGroup(
            children: _syncMode == _SyncMode.cloud
                ? _cloudTiles(sync)
                : [_p2pTile(context)],
          ),
        ],
      ),
    );
  }

  FTabEntry _modeTab(String label, IconData icon) => FTabEntry(
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
    child: const SizedBox.shrink(),
  );

  List<FTileMixin> _cloudTiles(SyncProvider sync) => [
    settingsContentTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsCaption('Supabase Backend'),
          const SizedBox(height: YsSpace.s2),
          FTextField(
            key: const ValueKey('sync-url-field'),
            control: .managed(controller: _urlController),
            size: .sm,
            hint: 'Project URL',
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            suffixBuilder: (context, style, variants) => _urlHasText
                ? SettingsIconButton(
                    icon: FLucideIcons.x,
                    tooltip: 'Clear URL',
                    onPress: _urlController.clear,
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(horizontal: YsSpace.s2),
                    child: Icon(
                      FLucideIcons.link,
                      size: 16,
                      color: YsColors.mutedForeground,
                    ),
                  ),
          ),
          const SizedBox(height: YsSpace.s2),
          Row(
            children: [
              Expanded(
                child: _secretField(
                  key: const ValueKey('sync-anon-key-field'),
                  controller: _anonKeyController,
                  hint: 'Anon key',
                  shown: _showAnonKey,
                  onShownChanged: (v) => setState(() => _showAnonKey = v),
                  what: 'anon key',
                ),
              ),
              const SizedBox(width: YsSpace.s2),
              FButton(
                key: const ValueKey('sync-save-test'),
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                prefix: _testing ? const FCircularProgress(size: .sm) : null,
                onPress: _testing ? null : _testAndSave,
                child: const Text('Save & Test'),
              ),
            ],
          ),
          if (_testing ||
              _testOk ||
              _needsServiceKey ||
              _testError != null) ...[
            const SizedBox(height: YsSpace.s2),
            _buildTestStatus(),
          ],
        ],
      ),
    ),
    if (sync.isSupabaseConfigured) ...[
      settingsContentTile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SettingsCaption('Sync code'),
            const SizedBox(height: YsSpace.s1),
            Text(
              sync.hasSyncCode
                  ? 'This 12-character code is the only key to your synced data. Enter it on another device to join.'
                  : 'Generate a code on this device, or enter one from another device. It is the only key to your data — save it.',
              style: TextStyle(
                color: sync.hasSyncCode
                    ? YsColors.mutedForeground
                    : YsColors.warn,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: YsSpace.s2),
            _secretField(
              key: const ValueKey('sync-code-field'),
              controller: _syncCodeController,
              hint: 'XXXX-XXXX-XXXX',
              shown: _showSyncCode,
              onShownChanged: (v) => setState(() => _showSyncCode = v),
              what: 'sync code',
              letterSpacing: 1.5,
              trailing: SettingsIconButton(
                key: const ValueKey('sync-copy-code'),
                icon: FLucideIcons.copy,
                tooltip: 'Copy',
                onPress: sync.hasSyncCode
                    ? () {
                        Clipboard.setData(ClipboardData(text: sync.syncCode));
                        showYsToast(
                          context,
                          'Sync code copied',
                          duration: const Duration(seconds: 1),
                        );
                      }
                    : null,
              ),
            ),
            const SizedBox(height: YsSpace.s2),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    key: const ValueKey('sync-save-code'),
                    size: .sm,
                    onPress: _saveCode,
                    child: const Text('Save code'),
                  ),
                ),
                const SizedBox(width: YsSpace.s2),
                Expanded(
                  child: FButton(
                    key: const ValueKey('sync-generate'),
                    variant: .outline,
                    size: .sm,
                    onPress: sync.hasSyncCode ? _regenerate : _generateCode,
                    child: Text(sync.hasSyncCode ? 'Regenerate' : 'Generate'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (sync.status != SyncStatus.idle)
        settingsContentTile(child: _SyncStatusRow(sync: sync)),
    ],
  ];

  /// Obscured secret field with a tooltipped show/hide toggle and an
  /// optional extra suffix button.
  Widget _secretField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required bool shown,
    required ValueChanged<bool> onShownChanged,
    required String what,
    double? letterSpacing,
    Widget? trailing,
  }) {
    return FTextField.password(
      key: key,
      control: .managed(controller: controller),
      obscureTextControl: .lifted(
        value: !shown,
        onChange: (obscured) => onShownChanged(!obscured),
      ),
      size: .sm,
      label: null,
      hint: hint,
      autofillHints: const [],
      textInputAction: TextInputAction.done,
      style: letterSpacing == null
          ? const .context()
          : .delta(
              contentTextStyle: .delta([
                .base(.delta(letterSpacing: letterSpacing)),
              ]),
            ),
      suffixBuilder: (context, style, obscure, variants) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: obscure.value ? 'Show $what' : 'Hide $what',
            excludeFromSemantics: true,
            child: FTextField.defaultObscureIconBuilder(
              context,
              style,
              obscure,
              variants,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildTestStatus() {
    if (_testing) return const SizedBox.shrink();
    if (_testOk) {
      return Row(
        children: [
          const Icon(
            FLucideIcons.circleCheck,
            size: 12,
            color: AppColors.success,
          ),
          const SizedBox(width: 4),
          const Text(
            'Connected',
            style: TextStyle(color: AppColors.success, fontSize: 12),
          ),
          const SizedBox(width: YsSpace.s3),
          FButton(
            key: const ValueKey('sync-disconnect'),
            variant: .destructive,
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            onPress: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      );
    }
    if (_needsServiceKey) {
      final projectRef =
          Uri.tryParse(_urlController.text.trim())?.host.split('.').first ?? '';
      final sqlEditorUrl = projectRef.isNotEmpty
          ? 'https://supabase.com/dashboard/project/$projectRef/sql/new'
          : 'https://supabase.com/dashboard';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FLucideIcons.info, size: 12, color: YsColors.warn),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Table not found. Copy the SQL below and run it in Supabase SQL Editor, then click Save & Test again:',
                  style: TextStyle(color: YsColors.warn, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(YsSpace.s2),
            decoration: BoxDecoration(
              color: YsColors.background,
              borderRadius: BorderRadius.circular(YsRadius.control),
              border: Border.all(color: YsColors.border),
            ),
            child: const Text(
              SupabaseService.migrationSql,
              style: TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 10,
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
              ),
            ),
          ),
          const SizedBox(height: YsSpace.s1),
          Wrap(
            spacing: YsSpace.s2,
            children: [
              FButton(
                variant: .ghost,
                size: .xs,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.copy),
                onPress: () => Clipboard.setData(
                  const ClipboardData(text: SupabaseService.migrationSql),
                ),
                child: const Text('Copy SQL'),
              ),
              FButton(
                variant: .ghost,
                size: .xs,
                mainAxisSize: MainAxisSize.min,
                prefix: const Icon(FLucideIcons.externalLink),
                onPress: () => launchUrl(Uri.parse(sqlEditorUrl)),
                child: const Text('Open SQL Editor'),
              ),
            ],
          ),
        ],
      );
    }
    if (_testError != null) {
      return Row(
        children: [
          const Icon(FLucideIcons.circleAlert, size: 12, color: YsColors.error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _testError!,
              style: const TextStyle(color: YsColors.error, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  FTile _p2pTile(BuildContext context) => settingsContentTile(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Transfer all hosts and passwords to another device over LAN or Tailscale. No cloud required.',
          style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        ),
        const SizedBox(height: YsSpace.s3),
        Row(
          children: [
            Expanded(
              child: FButton(
                key: const ValueKey('sync-show-qr'),
                variant: .outline,
                size: .sm,
                prefix: const Icon(FLucideIcons.qrCode),
                onPress: () => _showQrExport(context),
                child: settingsButtonText('Show QR Code'),
              ),
            ),
            const SizedBox(width: YsSpace.s3),
            Expanded(
              child: FButton(
                key: const ValueKey('sync-import-code'),
                variant: .outline,
                size: .sm,
                prefix: const Icon(FLucideIcons.clipboardPaste),
                onPress: () => showYsDialog<void>(
                  context,
                  builder: (_) => const QrImportDialog(),
                ),
                child: settingsButtonText('Import via Code'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SyncStatusRow extends StatelessWidget {
  final SyncProvider sync;
  const _SyncStatusRow({required this.sync});

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: YsColors.mutedForeground, fontSize: 12);
    switch (sync.status) {
      case SyncStatus.syncing:
        return const Row(
          children: [
            FCircularProgress(size: .sm),
            SizedBox(width: 6),
            Text('Syncing…', style: muted),
          ],
        );
      case SyncStatus.synced:
        final ago = sync.lastSynced == null ? '' : _ago(sync.lastSynced!);
        return Row(
          children: [
            const Icon(
              FLucideIcons.circleCheck,
              size: 12,
              color: AppColors.success,
            ),
            const SizedBox(width: 6),
            Text('Synced$ago', style: muted),
          ],
        );
      case SyncStatus.error:
        return Row(
          children: [
            const Icon(
              FLucideIcons.circleAlert,
              size: 12,
              color: YsColors.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Sync error: ${sync.error ?? ''}',
                style: const TextStyle(color: YsColors.error, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case SyncStatus.idle:
        return const SizedBox.shrink();
    }
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return ' · just now';
    if (diff.inMinutes < 60) return ' · ${diff.inMinutes}m ago';
    return ' · ${diff.inHours}h ago';
  }
}

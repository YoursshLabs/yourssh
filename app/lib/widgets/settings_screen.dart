import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/ai_provider_config.dart';
import '../providers/ai_chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import '../services/sync_code.dart';
import '../providers/host_provider.dart';
import '../services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'hotkey_settings_screen.dart';
import 'terminal_appearance_controls.dart';
import 'qr_export_dialog.dart';
import 'qr_import_dialog.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/update_provider.dart';
import '../models/app_release.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final sync = context.watch<SyncProvider>();
    final update = context.watch<UpdateProvider>();

    return Material(
      color: AppColors.bg,
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.sidebar,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Text('Settings', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _Section(title: 'Connection', children: [
                  _Row(
                    label: 'Auto-reconnect',
                    subtitle: 'Reconnect when connection drops',
                    trailing: Switch(
                      value: settings.autoReconnect,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => context.read<SettingsProvider>().save(autoReconnect: v),
                    ),
                  ),
                  _Row(
                    label: 'Max reconnect attempts',
                    trailing: _DropDown<int>(
                      value: settings.reconnectAttempts,
                      items: [0, 1, 3, 5, 10],
                      labelOf: (n) => n == 0 ? 'Unlimited' : '$n times',
                      onChanged: (v) => context.read<SettingsProvider>().save(reconnectAttempts: v),
                    ),
                  ),
                  _Row(
                    label: 'Keep-alive interval',
                    subtitle: 'How often to ping the server to keep the connection alive',
                    trailing: _DropDown<int>(
                      value: settings.keepAliveInterval,
                      items: [10, 30, 60, 0],
                      labelOf: (n) => n == 0 ? 'Off' : '${n}s',
                      onChanged: (v) => context.read<SettingsProvider>().save(keepAliveInterval: v),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Tmux Integration', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Attach to tmux session on connect (requires tmux on server)', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.tmuxEnabled,
                    onChanged: (v) {
                      settings.tmuxEnabled = v;
                      settings.save();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Shell Integration', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Detect cwd, command status & exit codes on bash/zsh (cwd in tab, gutter markers, jump-to-prompt, path completion)', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.shellIntegrationEnabled,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .save(shellIntegrationEnabled: v),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Terminal', children: [
                  _Row(
                    label: 'Terminal emulation type',
                    subtitle: 'TERM reported to the server — applies to new SSH connections',
                    trailing: _DropDown<String>(
                      value: settings.terminalType,
                      items: const ['xterm-256color', 'xterm', 'linux', 'vt100'],
                      labelOf: (t) => t,
                      onChanged: (v) => context.read<SettingsProvider>().save(terminalType: v),
                    ),
                  ),
                  const TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Recording', children: [
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) => _Row(
                      label: 'Recording path',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              settings.recordingPath,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final result = await FilePicker.platform.getDirectoryPath(
                                dialogTitle: 'Choose recordings folder',
                              );
                              if (result != null && context.mounted) {
                                await context.read<SettingsProvider>().save(recordingPath: result);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: AppColors.textSecondary,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: const Text('Change…'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Monitoring', children: [
                  SwitchListTile(
                    title: const Text('Network Stats Monitor', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Show Rx/Tx overlay on active session', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.networkStatsEnabled,
                    onChanged: (v) {
                      settings.networkStatsEnabled = v;
                      settings.save();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Command finish notification', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Alert when a command completes in an unfocused session', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.commandNotificationsEnabled,
                    onChanged: (v) => context.read<SettingsProvider>().save(commandNotificationsEnabled: v),
                  ),
                ]),
                const SizedBox(height: 24),
                _SyncSection(sync: sync),
                const SizedBox(height: 24),
                const _AiProvidersSection(),
                const SizedBox(height: 24),
                _Section(title: 'Keyboard', children: [
                  _Row(
                    label: 'Keyboard Shortcuts',
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.keyboard_outlined, size: 14),
                      label: const Text('Configure', style: TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HotkeySettingsScreen()),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Updates', children: [
                  _Row(
                    label: 'Current version',
                    trailing: Text(
                      'v${update.currentVersion}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  _Row(
                    label: 'Status',
                    subtitle: _updateStatusText(update),
                    trailing: update.status == UpdateStatus.downloading
                        ? SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(value: update.downloadProgress),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (update.status == UpdateStatus.available) ...[
                                FilledButton(
                                  onPressed: () =>
                                      context.read<UpdateProvider>().downloadAndInstall(),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.black,
                                    textStyle: const TextStyle(fontSize: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  child: const Text('Download & install'),
                                ),
                                const SizedBox(width: 8),
                              ],
                              OutlinedButton(
                                onPressed: update.status == UpdateStatus.checking
                                    ? null
                                    : () => context
                                        .read<UpdateProvider>()
                                        .checkForUpdates(manual: true),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.border),
                                  foregroundColor: AppColors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: const Text('Check for updates'),
                              ),
                            ],
                          ),
                  ),
                  if (update.status == UpdateStatus.available &&
                      update.latestRelease != null &&
                      update.latestRelease!.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        update.latestRelease!.notes,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _updateStatusText(UpdateProvider u) {
    switch (u.status) {
      case UpdateStatus.checking:
        return 'Checking…';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.available:
        return 'New version v${u.latestRelease?.version ?? '?'} available';
      case UpdateStatus.downloading:
        return 'Downloading…';
      case UpdateStatus.readyToInstall:
        return 'Installer opened — complete it to finish updating';
      case UpdateStatus.error:
        return u.errorMessage ?? 'Could not check for updates';
      case UpdateStatus.idle:
        return 'Click "Check for updates" to look for a new version';
    }
  }

}

class _SyncSection extends StatefulWidget {
  final SyncProvider sync;
  const _SyncSection({required this.sync});

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

enum _SyncMode { cloud, p2p }

class _SyncSectionState extends State<_SyncSection> {
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


  @override
  void initState() {
    super.initState();
    _urlController.text = widget.sync.supabaseUrl;
    _anonKeyController.text = widget.sync.supabaseAnonKey;
    _syncCodeController.text = SyncCode.format(widget.sync.syncCode);
    if (widget.sync.isSupabaseConfigured) _testOk = true;
    _urlHasText = _urlController.text.isNotEmpty;
    _urlController.addListener(() {
      final has = _urlController.text.isNotEmpty;
      if (has != _urlHasText) setState(() => _urlHasText = has);
    });
  }

  @override
  void didUpdateWidget(_SyncSection old) {
    super.didUpdateWidget(old);
    if (SyncCode.normalize(_syncCodeController.text) != widget.sync.syncCode) {
      _syncCodeController.text = SyncCode.format(widget.sync.syncCode);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid 12-character sync code.'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    final provider = context.read<SyncProvider>();
    await provider.setSyncCode(_syncCodeController.text);
    if (!mounted) return;
    setState(() => _syncCodeController.text = SyncCode.format(provider.syncCode));
    await _pushNow();
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Regenerate sync code?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        content: const Text(
          'A new code creates a new cloud record. Data tied to the old code '
          'becomes unreachable until you re-enter the old code.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (ok == true) await _generateCode();
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
      setState(() { _testError = 'URL and Anon key are required'; _testOk = false; });
      return;
    }
    setState(() { _testing = true; _testError = null; _testOk = false; _needsServiceKey = false; });
    try {
      final svc = SupabaseService(url, anonKey, '');
      final (outcome, error) = await svc.testConnection();
      if (!mounted) return;

      if (outcome == TestConnectionOutcome.connected) {
        await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
        if (!mounted) return;
        await _pushNow();
        if (!mounted) return;
        setState(() { _testing = false; _testOk = true; });
        return;
      }

      if (outcome == TestConnectionOutcome.tableNotFound) {
        setState(() { _testing = false; _needsServiceKey = true; });
        return;
      }

      setState(() { _testing = false; _testError = error ?? 'Connection failed'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _testing = false; _testError = e.toString(); });
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

  Widget _buildTestStatus() {
    if (_testing) return const SizedBox.shrink();
    if (_testOk) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 12, color: Colors.green),
        const SizedBox(width: 4),
        const Text('Connected', style: TextStyle(color: Colors.green, fontSize: 11)),
        const SizedBox(width: 12),
        TextButton(
          onPressed: _disconnect,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: Colors.red,
          ),
          child: const Text('Disconnect', style: TextStyle(fontSize: 11)),
        ),
      ]);
    }
    if (_needsServiceKey) {
      final projectRef = Uri.tryParse(_urlController.text.trim())?.host.split('.').first ?? '';
      final sqlEditorUrl = projectRef.isNotEmpty
          ? 'https://supabase.com/dashboard/project/$projectRef/sql/new'
          : 'https://supabase.com/dashboard';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.info_outline, size: 12, color: Colors.orange),
            SizedBox(width: 4),
            Flexible(child: Text(
              'Table not found. Copy the SQL below and run it in Supabase SQL Editor, then click Save & Test again:',
              style: TextStyle(color: Colors.orange, fontSize: 11),
            )),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              SupabaseService.migrationSql,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: SupabaseService.migrationSql));
                },
                icon: const Icon(Icons.copy, size: 12, color: AppColors.textSecondary),
                label: const Text('Copy SQL', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(sqlEditorUrl)),
                icon: const Icon(Icons.open_in_new, size: 12, color: AppColors.accent),
                label: const Text('Open SQL Editor', style: TextStyle(color: AppColors.accent, fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (_testError != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 12, color: Colors.red),
        const SizedBox(width: 4),
        Flexible(child: Text(_testError!, style: const TextStyle(color: Colors.red, fontSize: 11), overflow: TextOverflow.ellipsis)),
      ]);
    }
    return const SizedBox.shrink();
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

  Widget _buildModeTab(String label, IconData icon, _SyncMode mode) {
    final selected = _syncMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _syncMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? AppColors.accent : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: selected ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: selected ? AppColors.accent : AppColors.textSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }


  /// Shared decoration for the sync text fields (URL / anon key / sync code).
  InputDecoration _syncFieldDecoration({required String hint, Widget? suffixIcon}) {
    OutlineInputBorder borderWith(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color));
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
      filled: true,
      fillColor: AppColors.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: borderWith(AppColors.border),
      enabledBorder: borderWith(AppColors.border),
      focusedBorder: borderWith(AppColors.accent),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SYNC', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // ── Mode selector ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _buildModeTab('Cloud Sync', Icons.cloud_sync, _SyncMode.cloud),
                      const SizedBox(width: 8),
                      _buildModeTab('P2P Transfer', Icons.wifi_tethering, _SyncMode.p2p),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                if (_syncMode == _SyncMode.cloud)
                  _buildCloudTab(sync)
                else
                  _buildP2pTab(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudTab(SyncProvider sync) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Supabase Backend', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: _syncFieldDecoration(
              hint: 'Project URL',
              suffixIcon: _urlHasText
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: AppColors.textTertiary),
                      onPressed: () => _urlController.clear(),
                    )
                  : const Icon(Icons.link, size: 16, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _anonKeyController,
                  obscureText: !_showAnonKey,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: _syncFieldDecoration(
                    hint: 'Anon key',
                    suffixIcon: IconButton(
                      icon: Icon(_showAnonKey ? Icons.visibility_off : Icons.visibility, size: 16, color: AppColors.textTertiary),
                      onPressed: () => setState(() => _showAnonKey = !_showAnonKey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                height: 36,
                child: ElevatedButton(
                  onPressed: _testing ? null : _testAndSave,
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: _testing
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save & Test', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (_testing || _testOk || _needsServiceKey || _testError != null) ...[
            const SizedBox(height: 6),
            _buildTestStatus(),
          ],
          if (sync.isSupabaseConfigured) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            const Text(
              'Sync code',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              sync.hasSyncCode
                  ? 'This 12-character code is the only key to your synced data. Enter it on another device to join.'
                  : 'Generate a code on this device, or enter one from another device. It is the only key to your data — save it.',
              style: TextStyle(
                color: sync.hasSyncCode ? AppColors.textTertiary : Colors.orange,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _syncCodeController,
              obscureText: !_showSyncCode,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13, letterSpacing: 1.5),
              decoration: _syncFieldDecoration(
                hint: 'XXXX-XXXX-XXXX',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_showSyncCode ? Icons.visibility_off : Icons.visibility,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () => setState(() => _showSyncCode = !_showSyncCode),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 15, color: AppColors.textTertiary),
                      tooltip: 'Copy',
                      onPressed: sync.hasSyncCode
                          ? () {
                              Clipboard.setData(ClipboardData(text: sync.syncCode));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Sync code copied'),
                                  duration: Duration(seconds: 1)));
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _saveCode,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('Save code', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: sync.hasSyncCode ? _regenerate : _generateCode,
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(sync.hasSyncCode ? 'Regenerate' : 'Generate',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            _SyncStatusRow(sync: sync),
          ],
        ],
      ),
    );
  }

  Widget _buildP2pTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transfer all hosts and passwords to another device over LAN or Tailscale. No cloud required.',
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final SyncProvider sync;
  const _SyncStatusRow({required this.sync});

  @override
  Widget build(BuildContext context) {
    switch (sync.status) {
      case SyncStatus.syncing:
        return const Row(children: [
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
          SizedBox(width: 6),
          Text('Syncing…', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ]);
      case SyncStatus.synced:
        final ago = sync.lastSynced == null ? '' : _ago(sync.lastSynced!);
        return Row(children: [
          const Icon(Icons.check_circle, size: 12, color: Colors.green),
          const SizedBox(width: 6),
          Text('Synced$ago', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ]);
      case SyncStatus.error:
        return Row(children: [
          const Icon(Icons.error_outline, size: 12, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(child: Text('Sync error: ${sync.error ?? ''}', style: const TextStyle(color: Colors.red, fontSize: 11), overflow: TextOverflow.ellipsis)),
        ]);
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

class _AiProvidersSection extends StatefulWidget {
  const _AiProvidersSection();

  @override
  State<_AiProvidersSection> createState() => _AiProvidersSectionState();
}

class _AiProvidersSectionState extends State<_AiProvidersSection> {
  final _controllers = <AiProvider, TextEditingController>{};
  final _focusNodes = <AiProvider, FocusNode>{};
  final _showKey = <AiProvider, bool>{};

  @override
  void initState() {
    super.initState();
    for (final p in AiProvider.values) {
      _controllers[p] = TextEditingController();
      _showKey[p] = false;
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus && mounted) _saveKey(p);
      });
      _focusNodes[p] = node;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configs = context.read<AiChatProvider>().configs;
    for (final p in AiProvider.values) {
      if (_controllers[p]!.text.isEmpty && configs[p] != null) {
        _controllers[p]!.text = configs[p]!.apiKey;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _saveKey(AiProvider p) {
    final key = _controllers[p]!.text.trim();
    if (key.isEmpty) return;
    context.read<AiChatProvider>().setProviderConfig(p, apiKey: key);
  }

  String _label(AiProvider p) => switch (p) {
        AiProvider.anthropic => 'Anthropic',
        AiProvider.openai => 'OpenAI',
        AiProvider.gemini => 'Google Gemini',
      };

  String _hint(AiProvider p) => switch (p) {
        AiProvider.anthropic => 'sk-ant-...',
        AiProvider.openai => 'sk-...',
        AiProvider.gemini => 'AIza...',
      };

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiChatProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI PROVIDERS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...AiProvider.values.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCard(context, ai, p),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AiChatProvider ai, AiProvider p) {
    final config = ai.configs[p];
    final models = AiChatProvider.presetModels[p]!;
    final selectedModel = config?.model ?? models.first;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _label(p),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (config != null)
                const Icon(Icons.check_circle, size: 14, color: Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controllers[p],
            focusNode: _focusNodes[p],
            obscureText: !_showKey[p]!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: _hint(p),
              hintStyle:
                  const TextStyle(color: AppColors.textTertiary, fontSize: 12),
              filled: true,
              fillColor: AppColors.bg,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _showKey[p]! ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _showKey[p] = !_showKey[p]!),
                  ),
                  if (config != null)
                    IconButton(
                      icon: const Icon(Icons.clear,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () {
                        _controllers[p]!.clear();
                        context.read<AiChatProvider>().clearProviderConfig(p);
                      },
                    ),
                ],
              ),
            ),
            onSubmitted: (_) => _saveKey(p),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Model',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: selectedModel,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
                dropdownColor: AppColors.card,
                underline: const SizedBox(),
                isDense: true,
                items: models
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m, style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    context.read<AiChatProvider>().setProviderConfig(p, model: v);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: children.indexed.map((e) {
                final (i, child) = e;
                return Column(children: [
                  child,
                  if (i < children.length - 1)
                    const Divider(height: 1, color: AppColors.border, indent: 16),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? trailing;
  const _Row({required this.label, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DropDown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final void Function(T) onChanged;
  const _DropDown({required this.value, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(labelOf(i)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}

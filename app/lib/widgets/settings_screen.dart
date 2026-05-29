import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import '../providers/host_provider.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _themes = ['Dracula', 'One Dark', 'Tokyo Night', 'Nord', 'Solarized Dark'];
  static const _bundledFonts = [
    'monospace',
    'MesloLGS NF',
    'DejaVu Sans Mono for Powerline',
    'Inconsolata for Powerline',
    'Meslo LG S for Powerline',
    'Source Code Pro for Powerline',
    'Ubuntu Mono derivative Powerline',
    'Roboto Mono for Powerline',
  ];
  static const _kCustom = '__custom__';

  final _customFontController = TextEditingController();
  bool _pendingCustom = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final font = context.read<SettingsProvider>().terminalFont;
    final isCustom = !_bundledFonts.contains(font);
    if (isCustom && _customFontController.text.isEmpty) {
      _customFontController.text = font;
    }
  }

  @override
  void dispose() {
    _customFontController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final sync = context.watch<SyncProvider>();

    return Container(
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
                      items: [1, 3, 5, 10],
                      labelOf: (n) => '$n times',
                      onChanged: (v) => context.read<SettingsProvider>().save(reconnectAttempts: v),
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
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Terminal', children: [
                  _Row(
                    label: 'Color theme',
                    trailing: _DropDown<String>(
                      value: settings.terminalTheme,
                      items: _themes,
                      labelOf: (t) => t,
                      onChanged: (v) => context.read<SettingsProvider>().save(terminalTheme: v),
                    ),
                  ),
                  _Row(
                    label: 'Font size: ${settings.fontSize.round()}pt',
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: settings.fontSize,
                        min: 10,
                        max: 24,
                        divisions: 14,
                        onChanged: (v) => context.read<SettingsProvider>().save(fontSize: v),
                      ),
                    ),
                  ),
                  _Row(
                    label: 'Terminal font',
                    trailing: _buildFontDropdown(context, settings),
                  ),
                  if (_pendingCustom || !_bundledFonts.contains(settings.terminalFont))
                    _Row(
                      label: 'Custom font name',
                      trailing: SizedBox(
                        width: 220,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customFontController,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Hack Nerd Font',
                                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  filled: true,
                                  fillColor: AppColors.bg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: () {
                                final name = _customFontController.text.trim();
                                if (name.isEmpty) return;
                                setState(() => _pendingCustom = false);
                                context.read<SettingsProvider>().save(terminalFont: name);
                              },
                              child: const Text('Apply', style: TextStyle(fontSize: 12)),
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
                ]),
                const SizedBox(height: 24),
                _SyncSection(sync: sync),
                const SizedBox(height: 24),
                _Section(title: 'About', children: [
                  const _Row(label: 'Version', trailing: Text('v0.1.0', style: TextStyle(color: AppColors.textTertiary, fontSize: 12))),
                  const _Row(label: 'Build', trailing: Text('Flutter + dartssh2', style: TextStyle(color: AppColors.textTertiary, fontSize: 12))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontDropdown(BuildContext context, SettingsProvider settings) {
    final isCustom = !_bundledFonts.contains(settings.terminalFont);
    final ddValue = (isCustom || _pendingCustom) ? _kCustom : settings.terminalFont;
    return DropdownButton<String>(
      value: ddValue,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: [
        ..._bundledFonts.map((f) => DropdownMenuItem(
          value: f,
          child: Text(f == 'monospace' ? 'System Default' : f, style: const TextStyle(fontSize: 12)),
        )),
        const DropdownMenuItem(
          value: _kCustom,
          child: Text('Custom…', style: TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (v) {
        if (v == _kCustom) {
          setState(() {
            _pendingCustom = true;
            _customFontController.clear();
          });
        } else if (v != null) {
          setState(() => _pendingCustom = false);
          context.read<SettingsProvider>().save(terminalFont: v);
        }
      },
    );
  }
}

class _SyncSection extends StatefulWidget {
  final SyncProvider sync;
  const _SyncSection({required this.sync});

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  final _codeController = TextEditingController();
  bool _connecting = false;
  String? _connectError;
  final _urlController = TextEditingController();
  final _anonKeyController = TextEditingController();
  bool _showAnonKey = false;
  bool _urlHasText = false;
  bool _testing = false;
  bool _testOk = false;
  String? _testError;
  bool _migrating = false;
  bool _tableCreated = false;
  final _serviceRoleKeyController = TextEditingController();
  bool _showServiceRoleKey = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.sync.supabaseUrl;
    _anonKeyController.text = widget.sync.supabaseAnonKey;
    if (widget.sync.isSupabaseConfigured) _testOk = true;
    _urlHasText = _urlController.text.isNotEmpty;
    _urlController.addListener(() {
      final has = _urlController.text.isNotEmpty;
      if (has != _urlHasText) setState(() => _urlHasText = has);
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _urlController.dispose();
    _anonKeyController.dispose();
    _serviceRoleKeyController.dispose();
    super.dispose();
  }

  Future<void> _onToggle(bool value) async {
    final sync = context.read<SyncProvider>();
    final syncService = context.read<SyncService>();
    if (!value) {
      await syncService.disableAndDelete();
    } else {
      await sync.setEnabled(true);
      if (!mounted || !sync.isSupabaseConfigured) return;
      final hostProvider = context.read<HostProvider>();
      final storage = context.read<StorageService>();
      final passwords = <String, String>{};
      for (final host in hostProvider.allHosts) {
        final pw = await storage.loadPassword(host.id);
        if (pw != null) passwords['pw_${host.id}'] = pw;
      }
      await syncService.push(
        hosts: hostProvider.allHosts,
        loadPasswords: () async => passwords,
      );
      syncService.restartRetryTimer();
    }
  }

  Future<void> _testAndSave() async {
    final url = _urlController.text.trim();
    final anonKey = _anonKeyController.text.trim();
    final serviceRoleKey = _serviceRoleKeyController.text.trim();
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() { _testError = 'URL and anon key are required'; _testOk = false; });
      return;
    }
    setState(() { _testing = true; _testError = null; _testOk = false; _tableCreated = false; });
    try {
      final svc = SupabaseService(url, anonKey);
      final (outcome, error) = await svc.testConnection();
      if (!mounted) return;

      if (outcome == TestConnectionOutcome.connected) {
        await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
        if (!mounted) return;
        setState(() { _testing = false; _testOk = true; });
        return;
      }

      if (outcome == TestConnectionOutcome.tableNotFound && serviceRoleKey.isNotEmpty) {
        setState(() { _testing = false; _migrating = true; });
        final (ok, migrateError) = await svc.setupSchema(serviceRoleKey);
        if (!mounted) return;
        if (!ok) {
          setState(() { _migrating = false; _testError = migrateError; });
          return;
        }
        final (outcome2, error2) = await svc.testConnection();
        if (!mounted) return;
        if (outcome2 == TestConnectionOutcome.connected) {
          await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
          if (!mounted) return;
          setState(() { _migrating = false; _testOk = true; _tableCreated = true; });
        } else {
          setState(() { _migrating = false; _testError = error2 ?? 'Connection failed after migration'; });
        }
        return;
      }

      final message = outcome == TestConnectionOutcome.tableNotFound
          ? 'Table not found. Add your Service Role Key above to auto-create it.'
          : (error ?? 'Connection failed');
      setState(() { _testing = false; _testError = message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _testing = false; _migrating = false; _testError = e.toString(); });
    }
  }

  Widget _buildTestStatus() {
    if (_migrating) {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
        SizedBox(width: 6),
        Text('Setting up database…', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ]);
    }
    if (_testing) return const SizedBox.shrink();
    if (_testOk) {
      final label = _tableCreated ? 'Connected (table created)' : 'Connected';
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 12, color: Colors.green),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.green, fontSize: 11)),
      ]);
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

  Future<void> _connect() async {
    final rawCode = _codeController.text.trim();
    if (rawCode.replaceAll('-', '').length < 12) {
      setState(() => _connectError = 'Code must be 12 characters');
      return;
    }
    setState(() { _connecting = true; _connectError = null; });
    final sync = context.read<SyncProvider>();
    final syncService = context.read<SyncService>();
    final hostProvider = context.read<HostProvider>();
    try {
      await sync.replaceSyncId(rawCode);
    } on ArgumentError catch (e) {
      setState(() { _connecting = false; _connectError = e.message.toString(); });
      return;
    }
    if (!sync.enabled) {
      await sync.setEnabled(true);
      if (!mounted) return;
    }
    final payload = await syncService.pull();
    if (!mounted) return;
    setState(() { _connecting = false; });
    if (sync.status == SyncStatus.error) {
      setState(() => _connectError = 'Invalid sync code, please check and try again');
    } else {
      if (payload != null) {
        await hostProvider.replaceAll(payload.hosts, payload.passwords);
      }
      _codeController.clear();
      setState(() => _connectError = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SYNC', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              // ── Enable Sync toggle ───────────────────────────
              SwitchListTile(
                title: const Text('Enable Sync', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                subtitle: Text(
                  sync.enabled && sync.isSupabaseConfigured
                      ? 'Sync hosts across devices'
                      : sync.enabled
                          ? 'Enter Supabase credentials below'
                          : 'Sync hosts across devices',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                value: sync.enabled,
                onChanged: _onToggle,
              ),
              if (sync.enabled) ...[
                const Divider(height: 1, color: AppColors.border, indent: 16),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Supabase backend config ──────────────
                      const Text('Supabase Backend', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Project URL',
                          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                          filled: true,
                          fillColor: AppColors.bg,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent)),
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
                              decoration: InputDecoration(
                                hintText: 'Publishable (Anon) key',
                                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                                filled: true,
                                fillColor: AppColors.bg,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent)),
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
                              onPressed: (_testing || _migrating) ? null : _testAndSave,
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
                      const SizedBox(height: 8),
                      TextField(
                        controller: _serviceRoleKeyController,
                        obscureText: !_showServiceRoleKey,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Service Role Key (optional — auto-creates table on first run)',
                          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                          filled: true,
                          fillColor: AppColors.bg,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent)),
                          suffixIcon: IconButton(
                            icon: Icon(_showServiceRoleKey ? Icons.visibility_off : Icons.visibility, size: 16, color: AppColors.textTertiary),
                            onPressed: () => setState(() => _showServiceRoleKey = !_showServiceRoleKey),
                          ),
                        ),
                      ),
                      if (_testing || _migrating || _testOk || _testError != null) ...[
                        const SizedBox(height: 6),
                        _buildTestStatus(),
                      ],
                      // ── Sync code & connect (only when configured) ──
                      if (sync.isSupabaseConfigured) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 16),
                        const Text('Sync Code', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(sync.syncCodeDisplay, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'monospace', letterSpacing: 2)),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: sync.syncCodeDisplay));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Sync code copied'), duration: Duration(seconds: 2)),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Copy', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('Enter this code on other devices to sync.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(height: 12),
                        _SyncStatusRow(sync: sync),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 16),
                        const Text('Connect to another device', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Enter sync code…',
                                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                  filled: true,
                                  fillColor: AppColors.bg,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _connecting ? null : _connect,
                              child: _connecting
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Connect', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        if (_connectError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_connectError!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
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

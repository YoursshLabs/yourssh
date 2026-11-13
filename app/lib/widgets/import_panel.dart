import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../util/import_parsers.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

// ── Public parser functions (also used by tests) ──────────

List<Host> parseSshConfig(String input) =>
    const SshConfigParser().parse(input).hosts;

List<Host> parseJsonHosts(String input) {
  if (input.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(input);
    final list = decoded is List ? decoded : [decoded];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) {
          final map = Map<String, dynamic>.from(e)..remove('id');
          return Host.fromJson({
            'label': map['label'] ?? '',
            'host': map['host'] ?? '',
            'port': map['port'] ?? 22,
            'username': map['username'] ?? 'root',
            'authType': map['authType'] ?? 'password',
            'group': map['group'] ?? '',
            'tags': map['tags'] ?? [],
            'createdAt': DateTime.now().toIso8601String(),
          });
        })
        .where((h) => h.host.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

({List<Host> hosts, List<String> warnings}) parseCsvHosts(String input) =>
    const CsvParser().parse(input);

List<Host> detectAndParse(String input) {
  final trimmed = input.trimLeft();
  if (trimmed.toLowerCase().startsWith('host ')) return parseSshConfig(input);
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) return parseJsonHosts(input);
  final firstLine = trimmed.split('\n').first;
  if (firstLine.contains(',')) {
    try {
      return parseCsvHosts(input).hosts;
    } on FormatException {
      return [];
    }
  }
  return [];
}

// ── ImportSource registry ─────────────────────────────────

enum ImportSource {
  sshConfig, csv, putty, mobaXterm, secureCrt,
  ansible, winScp, termius, sshUri,
}

class ImportSourceDef {
  final ImportSource source;
  final String label;
  final IconData icon;
  final List<String> fileExtensions;
  final String hint;
  final ImportParser parser;

  const ImportSourceDef({
    required this.source,
    required this.label,
    required this.icon,
    required this.fileExtensions,
    required this.hint,
    required this.parser,
  });

  static final List<ImportSourceDef> all = [
    ImportSourceDef(
      source: ImportSource.sshConfig,
      label: '~/.ssh',
      icon: FLucideIcons.terminal,
      fileExtensions: ['config', 'conf', 'txt'],
      hint: 'Paste your ~/.ssh/config content or pick the file.',
      parser: const SshConfigParser(),
    ),
    ImportSourceDef(
      source: ImportSource.csv,
      label: 'CSV',
      icon: FLucideIcons.table,
      fileExtensions: ['csv', 'txt'],
      hint: 'Columns: host, label, port, username, auth_type, group, tags.',
      parser: const CsvParser(),
    ),
    ImportSourceDef(
      source: ImportSource.putty,
      label: 'PuTTY',
      icon: FLucideIcons.monitor,
      fileExtensions: ['reg', 'txt'],
      hint: 'Export from PuTTY: Connection → SSH → Export all settings.',
      parser: const PuttyRegParser(),
    ),
    ImportSourceDef(
      source: ImportSource.mobaXterm,
      label: 'MobaXterm',
      icon: FLucideIcons.layoutGrid,
      fileExtensions: ['mxtsessions', 'txt'],
      hint: 'Export from MobaXterm: Tools → Export all sessions.',
      parser: const MobaXtermParser(),
    ),
    ImportSourceDef(
      source: ImportSource.secureCrt,
      label: 'SecureCRT',
      icon: FLucideIcons.lock,
      fileExtensions: ['xml', 'txt'],
      hint: 'Export from SecureCRT: Tools → Export Sessions as XML.',
      parser: const SecureCrtParser(),
    ),
    ImportSourceDef(
      source: ImportSource.ansible,
      label: 'Ansible',
      icon: FLucideIcons.settings,
      fileExtensions: ['ini', 'yml', 'yaml', 'txt'],
      hint: 'Paste your Ansible INI inventory file.',
      parser: const AnsibleParser(),
    ),
    ImportSourceDef(
      source: ImportSource.winScp,
      label: 'WinSCP',
      icon: FLucideIcons.arrowLeftRight,
      fileExtensions: ['ini', 'txt'],
      hint: 'Export from WinSCP: Tools → Export/Backup Configuration.',
      parser: const WinScpParser(),
    ),
    ImportSourceDef(
      source: ImportSource.termius,
      label: 'Termius',
      icon: FLucideIcons.smartphone,
      fileExtensions: ['termius', 'json', 'txt'],
      hint: 'Export from Termius: Settings → Export Hosts.',
      parser: const TermiusParser(),
    ),
    ImportSourceDef(
      source: ImportSource.sshUri,
      label: 'SSH URI',
      icon: FLucideIcons.link,
      fileExtensions: ['txt'],
      hint: 'One URI per line: ssh://user@host:port',
      parser: const SshUriParser(),
    ),
  ];
}

// ── ImportPanel widget ────────────────────────────────────

class ImportPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ImportPanel({super.key, required this.onClose});

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

enum _InputMode { file, paste }

class _ImportPanelState extends State<ImportPanel> {
  ImportSource? _selectedSource;
  _InputMode _mode = _InputMode.file;
  final _pasteCtrl = TextEditingController();
  String? _parseError;
  List<Host> _parsed = [];
  final Map<int, bool> _included = {};
  final Map<int, bool> _overwrite = {};
  List<String> _csvWarnings = [];

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  bool _isDuplicate(Host h, List<Host> existing) => existing.any(
        (e) =>
            e.host.toLowerCase() == h.host.toLowerCase() &&
            e.username.toLowerCase() == h.username.toLowerCase(),
      );

  void _applyParsed(List<Host> hosts, {List<String> warnings = const []}) {
    setState(() {
      _parsed = hosts;
      _csvWarnings = List.of(warnings);
      _parseError = hosts.isEmpty && warnings.isEmpty
          ? 'No hosts found or unrecognized format'
          : (hosts.isEmpty && warnings.isNotEmpty ? 'All rows were skipped' : null);
      _included.clear();
      _overwrite.clear();
      for (var i = 0; i < hosts.length; i++) {
        _included[i] = true;
        _overwrite[i] = false;
      }
    });
  }

  void _parseInput(String input) {
    if (_selectedSource != null) {
      final def = ImportSourceDef.all.firstWhere((d) => d.source == _selectedSource);
      try {
        final result = def.parser.parse(input);
        _applyParsed(result.hosts, warnings: result.warnings);
      } on FormatException catch (e) {
        setState(() {
          _csvWarnings = [];
          _parsed = [];
          _parseError = e.message;
          _included.clear();
          _overwrite.clear();
        });
      }
      return;
    }

    // fallback: auto-detect (legacy path, still used when no source selected)
    final trimmed = input.trimLeft();
    final firstLine = trimmed.split('\n').first;
    final looksLikeCsv = firstLine.contains(',') &&
        !trimmed.toLowerCase().startsWith('host ') &&
        !trimmed.startsWith('[') &&
        !trimmed.startsWith('{');

    if (looksLikeCsv) {
      try {
        final result = parseCsvHosts(input);
        _applyParsed(result.hosts, warnings: result.warnings);
      } on FormatException catch (e) {
        setState(() {
          _csvWarnings = [];
          _parsed = [];
          _parseError = e.message;
          _included.clear();
          _overwrite.clear();
        });
      }
    } else {
      _applyParsed(detectAndParse(input));
    }
  }

  Future<void> _pickFile() async {
    final extensions = _selectedSource != null
        ? ImportSourceDef.all
            .firstWhere((d) => d.source == _selectedSource)
            .fileExtensions
        : ['json', 'config', 'conf', 'txt', 'csv'];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    _parseInput(utf8.decode(bytes));
  }

  void _parsePaste() => _parseInput(_pasteCtrl.text);

  int _effectiveImportCount(List<Host> existing) => _included.entries
      .where((e) => e.value)
      .where((e) {
        final dup = _isDuplicate(_parsed[e.key], existing);
        return !dup || (_overwrite[e.key] ?? false);
      })
      .length;

  void _resetResult() {
    _parsed = [];
    _parseError = null;
    _csvWarnings = [];
  }

  @override
  Widget build(BuildContext context) {
    final existingHosts = context.read<HostProvider>().allHosts;
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _selectedSource == null
                ? _buildSourcePicker()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        YsSpace.s4, YsSpace.s4, YsSpace.s4, YsSpace.s5),
                    children: [
                      _buildModeToggle(),
                      const SizedBox(height: YsSpace.s3),
                      if (_mode == _InputMode.file) _buildFileSection(),
                      if (_mode == _InputMode.paste) _buildPasteSection(),
                      if (_parseError != null) ...[
                        const SizedBox(height: YsSpace.s2),
                        Text(_parseError!,
                            style: const TextStyle(
                                color: YsColors.error, fontSize: 11)),
                      ],
                      if (_csvWarnings.isNotEmpty) ...[
                        const SizedBox(height: YsSpace.s2),
                        _buildWarnings(),
                      ],
                      if (_parsed.isNotEmpty) ...[
                        const SizedBox(height: YsSpace.s4),
                        _buildPreview(existingHosts),
                        const SizedBox(height: YsSpace.s4),
                        _buildImportButton(context, existingHosts),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePicker() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          YsSpace.s4, YsSpace.s4, YsSpace.s4, YsSpace.s5),
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.0,
          mainAxisSpacing: YsSpace.s2,
          crossAxisSpacing: YsSpace.s2,
          children: ImportSourceDef.all
              .map((def) => _SourceCard(
                    def: def,
                    onTap: () => setState(() {
                      _selectedSource = def.source;
                      _resetResult();
                    }),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final sourceDef = _selectedSource != null
        ? ImportSourceDef.all.firstWhere((d) => d.source == _selectedSource)
        : null;
    final title = sourceDef != null ? 'Import from ${sourceDef.label}' : 'Import Hosts';
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          if (sourceDef != null) ...[
            Tooltip(
              message: 'Back',
              excludeFromSemantics: true,
              child: FButton.icon(
                variant: .ghost,
                size: .sm,
                semanticsLabel: 'Back',
                onPress: () => setState(() {
                  _selectedSource = null;
                  _resetResult();
                }),
                child: const Icon(FLucideIcons.arrowLeft),
              ),
            ),
            const SizedBox(width: YsSpace.s2),
          ],
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: YsColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          Tooltip(
            message: 'Close',
            excludeFromSemantics: true,
            child: FButton.icon(
              variant: .ghost,
              size: .sm,
              semanticsLabel: 'Close',
              onPress: widget.onClose,
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    );
  }

  /// From file / Paste text: [FTabs] used as a segmented control (the tabs
  /// carry no content of their own).
  Widget _buildModeToggle() {
    return FTabs(
      key: const Key('import-mode-tabs'),
      control: .lifted(
        index: _mode.index,
        onChange: (i) => setState(() {
          _mode = _InputMode.values[i];
          _resetResult();
        }),
      ),
      children: [
        FTabEntry(
            label: const Text('From file'), child: const SizedBox.shrink()),
        FTabEntry(
            label: const Text('Paste text'), child: const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildFileSection() {
    final sourceDef = _selectedSource != null
        ? ImportSourceDef.all.firstWhere((d) => d.source == _selectedSource)
        : null;
    final extLabel = sourceDef != null
        ? sourceDef.fileExtensions.map((e) => '.$e').join(', ')
        : '.json, .csv, .config';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          key: const Key('import-choose-file'),
          variant: .outline,
          onPress: _pickFile,
          prefix: const Icon(FLucideIcons.upload),
          child: Flexible(
            child: Text('Choose file ($extLabel)',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (sourceDef != null) ...[
          const SizedBox(height: 6),
          Text(sourceDef.hint,
              style: const TextStyle(
                  color: YsColors.mutedForeground, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _buildPasteSection() {
    final hint = _selectedSource != null
        ? ImportSourceDef.all.firstWhere((d) => d.source == _selectedSource).hint
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FTextField.multiline(
          key: const Key('import-paste-field'),
          control: FTextFieldControl.managed(controller: _pasteCtrl),
          minLines: 10,
          maxLines: 10,
          autocorrect: false,
          enableSuggestions: false,
          hint: 'Paste SSH config, JSON, or CSV...',
          style: .delta(
            contentTextStyle: .delta([
              .all(.delta(
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
              )),
            ]),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint,
              style: const TextStyle(
                  color: YsColors.mutedForeground, fontSize: 11)),
        ],
        const SizedBox(height: YsSpace.s2),
        FButton(
          variant: .outline,
          onPress: _parsePaste,
          child: const Text('Parse'),
        ),
      ],
    );
  }

  Widget _buildWarnings() {
    return FAccordion(
      children: [
        FAccordionItem(
          title: Text(
            '${_csvWarnings.length} row${_csvWarnings.length == 1 ? '' : 's'} skipped — click to expand',
            style: const TextStyle(color: YsColors.warn, fontSize: 11),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _csvWarnings
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: YsSpace.s1),
                      child: Text(w,
                          style: const TextStyle(
                              color: YsColors.mutedForeground, fontSize: 11)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(List<Host> existingHosts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_parsed.length} host${_parsed.length == 1 ? '' : 's'} found',
          style: const TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8),
        ),
        const SizedBox(height: YsSpace.s2),
        Container(
          decoration: BoxDecoration(
            color: YsColors.card,
            borderRadius: BorderRadius.circular(YsRadius.card),
            border: Border.all(color: YsColors.border),
          ),
          child: Column(
            children: List.generate(_parsed.length, (i) {
              final h = _parsed[i];
              final dup = _isDuplicate(h, existingHosts);
              return _PreviewRow(
                host: h,
                isDuplicate: dup,
                included: _included[i] ?? true,
                overwrite: _overwrite[i] ?? false,
                onToggleInclude: (v) => setState(() => _included[i] = v),
                onToggleOverwrite: (v) => setState(() => _overwrite[i] = v),
                showDivider: i < _parsed.length - 1,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildImportButton(BuildContext context, List<Host> existingHosts) {
    final count = _effectiveImportCount(existingHosts);
    return FButton(
      key: const Key('import-submit'),
      variant: .primary,
      onPress: count == 0 ? null : () => _doImport(context),
      child: Text('IMPORT $count HOST${count == 1 ? '' : 'S'}'),
    );
  }

  Future<void> _doImport(BuildContext context) async {
    final provider = context.read<HostProvider>();
    final existingHosts = provider.allHosts.toList(); // snapshot once
    int imported = 0;
    for (var i = 0; i < _parsed.length; i++) {
      if (!(_included[i] ?? true)) continue;
      final h = _parsed[i];
      final dup = _isDuplicate(h, existingHosts);
      if (dup) {
        if (!(_overwrite[i] ?? false)) continue;
        final existing = existingHosts.firstWhere(
          (e) =>
              e.host.toLowerCase() == h.host.toLowerCase() &&
              e.username.toLowerCase() == h.username.toLowerCase(),
        );
        await provider.updateHost(existing.copyWith(
          label: h.label,
          host: h.host,
          port: h.port,
          username: h.username,
          group: h.group,
          agentForwarding: h.agentForwarding,
        ));
      } else {
        await provider.addHost(h);
      }
      imported++;
    }
    if (!context.mounted) return;
    showYsToast(context, 'Imported $imported host${imported == 1 ? '' : 's'}',
        kind: YsToastKind.success, duration: const Duration(seconds: 2));
    widget.onClose();
  }
}

// ── Source Card ───────────────────────────────────────────

class _SourceCard extends StatelessWidget {
  final ImportSourceDef def;
  final VoidCallback onTap;
  const _SourceCard({required this.def, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FTappable(
      semanticsLabel: 'Import from ${def.label}',
      onPress: onTap,
      builder: (context, variants, child) => Container(
        decoration: BoxDecoration(
          color: variants.contains(FTappableVariant.hovered) ||
                  variants.contains(FTappableVariant.focused)
              ? YsColors.secondary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(YsRadius.card),
          border: Border.all(color: YsColors.border),
        ),
        child: child,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(def.icon, color: YsColors.accentText, size: 28),
          const SizedBox(height: 6),
          Text(
            def.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: YsColors.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Preview Row ───────────────────────────────────────────

class _PreviewRow extends StatelessWidget {
  final Host host;
  final bool isDuplicate;
  final bool included;
  final bool overwrite;
  final ValueChanged<bool> onToggleInclude;
  final ValueChanged<bool> onToggleOverwrite;
  final bool showDivider;

  const _PreviewRow({
    required this.host,
    required this.isDuplicate,
    required this.included,
    required this.overwrite,
    required this.onToggleInclude,
    required this.onToggleOverwrite,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: YsSpace.s3 - 2, vertical: YsSpace.s2),
          child: Row(
            children: [
              FCheckbox(
                value: included,
                semanticsLabel: 'Include ${host.label}',
                onChange: onToggleInclude,
              ),
              const SizedBox(width: YsSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.label,
                        style: const TextStyle(
                            color: YsColors.foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${host.username}@${host.host}:${host.port}',
                      style: const TextStyle(
                          color: YsColors.mutedForeground, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isDuplicate && included) ...[
                const SizedBox(width: YsSpace.s1),
                FButton(
                  key: const Key('import-duplicate-toggle'),
                  variant: overwrite ? .secondary : .outline,
                  size: .xs,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => onToggleOverwrite(!overwrite),
                  child: Text(overwrite ? 'Overwrite' : 'Skip dup'),
                ),
              ],
            ],
          ),
        ),
        if (showDivider) const FDivider(),
      ],
    );
  }
}

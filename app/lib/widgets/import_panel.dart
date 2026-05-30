import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../theme/app_theme.dart';

// ── Public parser functions (also used by tests) ──────────

List<Host> parseSshConfig(String input) {
  final hosts = <Host>[];
  final blockRegex = RegExp(r'^Host\s+(.+)$', multiLine: true, caseSensitive: false);
  final matches = blockRegex.allMatches(input).toList();
  for (var i = 0; i < matches.length; i++) {
    final alias = matches[i].group(1)!.trim();
    if (alias == '*') continue;
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : input.length;
    final block = input.substring(start, end);
    String? hostname;
    String user = 'root';
    int port = 22;
    for (final line in block.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('hostname ')) {
        hostname = trimmed.substring('hostname '.length).trim();
      } else if (trimmed.toLowerCase().startsWith('user ')) {
        user = trimmed.substring('user '.length).trim();
      } else if (trimmed.toLowerCase().startsWith('port ')) {
        port = int.tryParse(trimmed.substring('port '.length).trim()) ?? 22;
      }
    }
    if (hostname == null) continue;
    hosts.add(Host(label: alias, host: hostname, port: port, username: user));
  }
  return hosts;
}

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

List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        sb.write('"');
        i += 2;
      } else {
        inQuotes = !inQuotes;
        i++;
      }
    } else if (ch == ',' && !inQuotes) {
      fields.add(sb.toString());
      sb.clear();
      i++;
    } else {
      sb.write(ch);
      i++;
    }
  }
  if (inQuotes) throw FormatException('Unterminated quote in CSV');
  fields.add(sb.toString());
  return fields;
}

({List<Host> hosts, List<String> warnings}) parseCsvHosts(String input) {
  final lines = input.split('\n').map((l) => l.trimRight()).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) { lines.removeLast(); }
  if (lines.isEmpty) return (hosts: [], warnings: []);

  final header = _splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase()).toList();
  if (!header.contains('host')) {
    throw FormatException("CSV missing required 'host' column");
  }

  int idx(String name) => header.indexOf(name);
  final hostIdx = idx('host');
  final labelIdx = idx('label');
  final portIdx = idx('port');
  final userIdx = idx('username');
  final authIdx = idx('auth_type');
  final groupIdx = idx('group');
  final tagsIdx = idx('tags');

  final hosts = <Host>[];
  final warnings = <String>[];

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    List<String> cells;
    try {
      cells = _splitCsvLine(line);
    } catch (_) {
      warnings.add('Row ${i + 1}: malformed CSV, skipped');
      continue;
    }

    String cell(int colIdx) =>
        colIdx >= 0 && colIdx < cells.length ? cells[colIdx].trim() : '';

    final hostVal = cell(hostIdx);
    if (hostVal.isEmpty) {
      warnings.add('Row ${i + 1}: missing host, skipped');
      continue;
    }

    int port = 22;
    final portStr = cell(portIdx);
    if (portStr.isNotEmpty) {
      final parsed = int.tryParse(portStr);
      if (parsed == null || parsed < 1 || parsed > 65535) {
        warnings.add("Row ${i + 1}: invalid port '$portStr', skipped");
        continue;
      }
      port = parsed;
    }

    final labelVal = cell(labelIdx);
    final authVal = cell(authIdx).toLowerCase();
    final tagsVal = cell(tagsIdx);

    final authType = switch (authVal) {
      'key' || 'privatekey' => AuthType.privateKey,
      'agent' => AuthType.agent,
      _ => AuthType.password,
    };

    final tags = tagsVal.isEmpty
        ? <String>[]
        : tagsVal.split(';').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    hosts.add(Host(
      label: labelVal.isEmpty ? hostVal : labelVal,
      host: hostVal,
      port: port,
      username: cell(userIdx),
      authType: authType,
      group: cell(groupIdx),
      tags: tags,
    ));
  }

  return (hosts: hosts, warnings: warnings);
}

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

// ── ImportPanel widget ────────────────────────────────────

class ImportPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ImportPanel({super.key, required this.onClose});

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

enum _InputMode { file, paste }

class _ImportPanelState extends State<ImportPanel> {
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'config', 'conf', 'txt', 'csv'],
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

  @override
  Widget build(BuildContext context) {
    final existingHosts = context.read<HostProvider>().allHosts;
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildModeToggle(),
                const SizedBox(height: 12),
                if (_mode == _InputMode.file) _buildFileSection(),
                if (_mode == _InputMode.paste) _buildPasteSection(),
                if (_parseError != null) ...[
                  const SizedBox(height: 8),
                  Text(_parseError!, style: const TextStyle(color: AppColors.red, fontSize: 11)),
                ],
                if (_csvWarnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildWarnings(),
                ],
                if (_parsed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildPreview(existingHosts),
                  const SizedBox(height: 16),
                  _buildImportButton(context, existingHosts),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('Import Hosts',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _modeTab('From file', _InputMode.file),
          _modeTab('Paste text', _InputMode.paste),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _InputMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = mode;
          _parsed = [];
          _parseError = null;
          _csvWarnings = [];
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildFileSection() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file_outlined, size: 16, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Choose file (.json, .csv, .config)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _pasteCtrl,
            maxLines: 10,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'Paste SSH config, JSON, or CSV...',
              hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              contentPadding: EdgeInsets.all(12),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _parsePaste,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: const Text('Parse', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildWarnings() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          '${_csvWarnings.length} row${_csvWarnings.length == 1 ? '' : 's'} skipped — click to expand',
          style: const TextStyle(color: Colors.orange, fontSize: 11),
        ),
        children: _csvWarnings
            .map((w) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(w,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildPreview(List<Host> existingHosts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_parsed.length} host${_parsed.length == 1 ? '' : 's'} found',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
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
    return GestureDetector(
      onTap: count == 0 ? null : () => _doImport(context),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: count == 0 ? AppColors.accentDim : AppColors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          'IMPORT $count HOST${count == 1 ? '' : 'S'}',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1),
        ),
      ),
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
        ));
      } else {
        await provider.addHost(h);
      }
      imported++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported $imported host${imported == 1 ? '' : 's'}'),
      duration: const Duration(seconds: 2),
    ));
    widget.onClose();
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: included,
                onChanged: (v) => onToggleInclude(v ?? true),
                side: const BorderSide(color: AppColors.textSecondary),
                activeColor: AppColors.accent,
                checkColor: Colors.black,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.label,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${host.username}@${host.host}:${host.port}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isDuplicate && included) ...[
                const SizedBox(width: 4),
                _DuplicateBadge(
                    overwrite: overwrite,
                    onToggle: () => onToggleOverwrite(!overwrite)),
              ],
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: AppColors.border, indent: 10),
      ],
    );
  }
}

class _DuplicateBadge extends StatelessWidget {
  final bool overwrite;
  final VoidCallback onToggle;

  const _DuplicateBadge({required this.overwrite, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: overwrite ? AppColors.blue.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: overwrite ? AppColors.blue.withValues(alpha: 0.5) : Colors.orange.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          overwrite ? 'Overwrite' : 'Skip dup',
          style: TextStyle(
              color: overwrite ? AppColors.blue : Colors.orange,
              fontSize: 9,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

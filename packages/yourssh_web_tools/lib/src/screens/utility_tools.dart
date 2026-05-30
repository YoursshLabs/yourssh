import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

@visibleForTesting
String encodeBase64(String input) => base64.encode(utf8.encode(input));

@visibleForTesting
String decodeBase64(String input) {
  try {
    return utf8.decode(base64.decode(input));
  } catch (_) {
    return 'Invalid Base64';
  }
}

@visibleForTesting
String encodeUrl(String input) => Uri.encodeComponent(input);

@visibleForTesting
String decodeUrl(String input) {
  try {
    return Uri.decodeComponent(input);
  } catch (_) {
    return 'Invalid URL encoding';
  }
}

@visibleForTesting
String formatJson(String input) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(input));
  } catch (_) {
    return 'Invalid JSON';
  }
}

@visibleForTesting
String minifyJson(String input) {
  try {
    return jsonEncode(jsonDecode(input));
  } catch (_) {
    return 'Invalid JSON';
  }
}

enum _UtilTab { base64, url, json, hash }

class UtilityTools extends StatefulWidget {
  const UtilityTools({super.key});

  @override
  State<UtilityTools> createState() => _UtilityToolsState();
}

class _UtilityToolsState extends State<UtilityTools> {
  _UtilTab _tab = _UtilTab.base64;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _UtilSubNav(active: _tab, onSelect: (t) => setState(() => _tab = t)),
        Container(width: 1, color: WebToolsColors.border),
        Expanded(child: _buildTab()),
      ],
    );
  }

  Widget _buildTab() => switch (_tab) {
        _UtilTab.base64 => const _Base64Tool(),
        _UtilTab.url    => const _UrlTool(),
        _UtilTab.json   => const _JsonTool(),
        _UtilTab.hash   => const _HashTool(),
      };
}

class _UtilSubNav extends StatelessWidget {
  final _UtilTab active;
  final ValueChanged<_UtilTab> onSelect;
  const _UtilSubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      color: WebToolsColors.card,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _item('Base64', _UtilTab.base64),
          _item('URL', _UtilTab.url),
          _item('JSON', _UtilTab.json),
          _item('Hash', _UtilTab.hash),
        ],
      ),
    );
  }

  Widget _item(String label, _UtilTab tab) {
    final sel = active == tab;
    return GestureDetector(
      onTap: () => onSelect(tab),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? WebToolsColors.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
              color: sel ? WebToolsColors.accent : WebToolsColors.textSecondary,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w500 : FontWeight.normal,
            )),
      ),
    );
  }
}

// ── Shared IO widget ──────────────────────────────────────

class _IoPane extends StatelessWidget {
  final String inputLabel;
  final String outputLabel;
  final TextEditingController inputCtrl;
  final String output;
  final List<Widget> actions;

  const _IoPane({
    required this.inputLabel,
    required this.outputLabel,
    required this.inputCtrl,
    required this.output,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(inputLabel,
              style: const TextStyle(color: WebToolsColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: WebToolsColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WebToolsColors.border),
              ),
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: inputCtrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                    color: WebToolsColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
                decoration:
                    const InputDecoration(border: InputBorder.none, isDense: true),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text(outputLabel,
                style: const TextStyle(color: WebToolsColors.textSecondary, fontSize: 11)),
            const Spacer(),
            ...actions,
            const SizedBox(width: 4),
            _CopyBtn(text: output),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: WebToolsColors.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WebToolsColors.border),
              ),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: const TextStyle(
                      color: WebToolsColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyBtn extends StatelessWidget {
  final String text;
  const _CopyBtn({required this.text});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy, size: 14),
      color: WebToolsColors.textSecondary,
      tooltip: 'Copy output',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () => Clipboard.setData(ClipboardData(text: text)),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: WebToolsColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: WebToolsColors.border),
        ),
        child: Text(label,
            style: const TextStyle(color: WebToolsColors.textSecondary, fontSize: 11)),
      ),
    );
  }
}

// ── Base64 ────────────────────────────────────────────────

class _Base64Tool extends StatefulWidget {
  const _Base64Tool();

  @override
  State<_Base64Tool> createState() => _Base64ToolState();
}

class _Base64ToolState extends State<_Base64Tool> {
  final _inputCtrl = TextEditingController();
  String _output = '';

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _encode() => setState(() => _output = encodeBase64(_inputCtrl.text));

  void _decode() => setState(() => _output = decodeBase64(_inputCtrl.text));

  @override
  Widget build(BuildContext context) => _IoPane(
        inputLabel: 'INPUT',
        outputLabel: 'OUTPUT',
        inputCtrl: _inputCtrl,
        output: _output,
        actions: [
          _ActionBtn(label: 'Encode', onTap: _encode),
          const SizedBox(width: 6),
          _ActionBtn(label: 'Decode', onTap: _decode),
        ],
      );
}

// ── URL Encode ────────────────────────────────────────────

class _UrlTool extends StatefulWidget {
  const _UrlTool();

  @override
  State<_UrlTool> createState() => _UrlToolState();
}

class _UrlToolState extends State<_UrlTool> {
  final _inputCtrl = TextEditingController();
  String _output = '';

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _encode() => setState(() => _output = encodeUrl(_inputCtrl.text));

  void _decode() => setState(() => _output = decodeUrl(_inputCtrl.text));

  @override
  Widget build(BuildContext context) => _IoPane(
        inputLabel: 'INPUT',
        outputLabel: 'OUTPUT',
        inputCtrl: _inputCtrl,
        output: _output,
        actions: [
          _ActionBtn(label: 'Encode', onTap: _encode),
          const SizedBox(width: 6),
          _ActionBtn(label: 'Decode', onTap: _decode),
        ],
      );
}

// ── JSON Formatter ────────────────────────────────────────

class _JsonTool extends StatefulWidget {
  const _JsonTool();

  @override
  State<_JsonTool> createState() => _JsonToolState();
}

class _JsonToolState extends State<_JsonTool> {
  final _inputCtrl = TextEditingController();
  String _output = '';

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _format() => setState(() => _output = formatJson(_inputCtrl.text));

  void _minify() => setState(() => _output = minifyJson(_inputCtrl.text));

  @override
  Widget build(BuildContext context) => _IoPane(
        inputLabel: 'INPUT',
        outputLabel: 'OUTPUT',
        inputCtrl: _inputCtrl,
        output: _output,
        actions: [
          _ActionBtn(label: 'Format', onTap: _format),
          const SizedBox(width: 6),
          _ActionBtn(label: 'Minify', onTap: _minify),
        ],
      );
}

// ── Hash ──────────────────────────────────────────────────

class _HashTool extends StatefulWidget {
  const _HashTool();

  @override
  State<_HashTool> createState() => _HashToolState();
}

class _HashToolState extends State<_HashTool> {
  final _inputCtrl = TextEditingController();
  String _output = '';

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _hash(HashAlgorithm algo, String label) async {
    final bytes = utf8.encode(_inputCtrl.text);
    final hash = await algo.hash(bytes);
    final hex =
        hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (!mounted) return;
    setState(() => _output = '$label:\n$hex');
  }

  @override
  Widget build(BuildContext context) => _IoPane(
        inputLabel: 'INPUT',
        outputLabel: 'HASH OUTPUT',
        inputCtrl: _inputCtrl,
        output: _output,
        actions: [
          _ActionBtn(label: 'SHA-256', onTap: () => _hash(Sha256(), 'SHA-256')),
          const SizedBox(width: 6),
          _ActionBtn(label: 'SHA-512', onTap: () => _hash(Sha512(), 'SHA-512')),
          const SizedBox(width: 6),
          _ActionBtn(label: 'SHA-1', onTap: () => _hash(Sha1(), 'SHA-1')),
        ],
      );
}

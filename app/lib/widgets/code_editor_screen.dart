// app/lib/widgets/code_editor_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../services/sftp_transfer_service.dart';

class CodeEditorScreen extends StatefulWidget {
  final Host host;
  final SftpEntry entry;

  const CodeEditorScreen({
    super.key,
    required this.host,
    required this.entry,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _saving = false;
  bool _isDirty = false;
  String? _content;

  static const _langMap = {
    'dart': 'dart', 'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown',
    'sh': 'shell', 'bash': 'shell', 'zsh': 'shell', 'go': 'go',
    'rs': 'rust', 'c': 'c', 'cpp': 'cpp', 'html': 'html', 'css': 'css',
    'xml': 'xml', 'sql': 'sql', 'toml': 'ini',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..loadFlutterAsset('assets/monaco_editor.html');
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final service = context.read<SftpTransferService>();
      final tmpPath = await service.downloadToTemp(widget.host, widget.entry);
      if (tmpPath == null || !mounted) return;
      final bytes = await File(tmpPath).readAsBytes();
      if (!mounted) return;
      setState(() => _content = utf8.decode(bytes, allowMalformed: true));
      if (_ready) _pushContentToEditor();
    } catch (e) {
      // The SFTP server returns SSH_FX_FAILURE (code 4) when the target is not
      // a readable regular file — e.g. a directory, a virtual/special file, or
      // a permission/IO error. Surface it and close the editor instead of
      // crashing with an unhandled exception (this runs fire-and-forget from
      // initState, so an uncaught error has nowhere to go).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot open ${widget.entry.name}: $e'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['type'] as String;
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) _pushContentToEditor();
    } else if (type == 'change') {
      if (!_isDirty) setState(() => _isDirty = true);
    } else if (type == 'save') {
      final content = data['content'] as String;
      _saveFile(content);
    }
  }

  void _pushContentToEditor() {
    final lang = _langMap[widget.entry.extension] ?? 'plaintext';
    final escaped = jsonEncode(_content);
    _controller.runJavaScript('loadContent($escaped, "$lang")');
  }

  Future<void> _saveFile(String content) async {
    setState(() => _saving = true);
    try {
      final service = context.read<SftpTransferService>();
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = '${tmpDir.path}/${widget.entry.name}';
      await File(tmpPath).writeAsString(content);
      await service.uploadFile(widget.host, tmpPath, widget.entry.path);
      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDiscardDialog() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Unsaved changes',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: const Text('Discard changes and close?',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showDiscardDialog();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        title: Text(
          widget.entry.name,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.save_outlined, size: 18),
            tooltip: 'Save (Ctrl+S)',
            onPressed: _saving
                ? null
                : () async {
                    final content = await _controller.runJavaScriptReturningResult('getContent()');
                    await _saveFile(content.toString());
                  },
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          : WebViewWidget(controller: _controller),
      ),
    );
  }
}

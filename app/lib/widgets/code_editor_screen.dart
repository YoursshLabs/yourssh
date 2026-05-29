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
    final service = context.read<SftpTransferService>();
    final tmpPath = await service.downloadToTemp(widget.host, widget.entry);
    if (tmpPath == null || !mounted) return;
    final bytes = await File(tmpPath).readAsBytes();
    setState(() => _content = utf8.decode(bytes, allowMalformed: true));
    if (_ready) _pushContentToEditor();
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['type'] as String;
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) _pushContentToEditor();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}

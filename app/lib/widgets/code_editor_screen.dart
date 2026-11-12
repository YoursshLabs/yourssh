// app/lib/widgets/code_editor_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../services/external_edit_service.dart';
import '../services/sftp_file_inspector.dart';
import '../services/sftp_transfer_service.dart';
import '../util/safe_local_path.dart';
import '../util/webview_result.dart';

import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class CodeEditorScreen extends StatefulWidget {
  final Host host;
  final SftpEntry entry;
  final bool readOnly;

  const CodeEditorScreen({
    super.key,
    required this.host,
    required this.entry,
    this.readOnly = false,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  // Monaco runs in a webview where an implementation exists (macOS, mobile).
  // On Linux/Windows webview_flutter has no platform implementation —
  // constructing WebViewController there throws and used to blank the whole
  // window (issue #34) — so we fall back to a plain TextField editor.
  WebViewController? _controller;
  final TextEditingController _textController = TextEditingController();
  bool _ready = false;
  bool _saving = false;
  bool _isDirty = false;
  String? _content;
  String? _tmpPath;

  bool get _useWebView => _controller != null;

  static const _langMap = {
    'dart': 'dart',
    'py': 'python',
    'js': 'javascript',
    'ts': 'typescript',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'md': 'markdown',
    'sh': 'shell',
    'bash': 'shell',
    'zsh': 'shell',
    'go': 'go',
    'rs': 'rust',
    'c': 'c',
    'cpp': 'cpp',
    'html': 'html',
    'css': 'css',
    'xml': 'xml',
    'sql': 'sql',
    'toml': 'ini',
  };

  @override
  void initState() {
    super.initState();
    if (WebViewPlatform.instance != null) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'FlutterChannel',
          onMessageReceived: _onJsMessage,
        )
        ..loadFlutterAsset('assets/monaco_editor.html');
    }
    _loadFile();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final service = context.read<SftpTransferService>();
      final tmpPath = await service.downloadToTemp(widget.host, widget.entry);
      if (tmpPath == null || !mounted) return;
      _tmpPath = tmpPath;
      final bytes = await File(tmpPath).readAsBytes();
      if (!mounted) return;
      if (looksBinary(bytes)) {
        await _offerExternalOpen();
        return;
      }
      setState(() => _content = utf8.decode(bytes, allowMalformed: true));
      if (_useWebView) {
        if (_ready) {
          _pushContentToEditor();
        }
      } else {
        _textController.text = _content!;
        setState(() => _ready = true);
      }
    } catch (e) {
      // The SFTP server returns SSH_FX_FAILURE (code 4) when the target is not
      // a readable regular file — e.g. a directory, a virtual/special file, or
      // a permission/IO error. Surface it and close the editor instead of
      // crashing with an unhandled exception (this runs fire-and-forget from
      // initState, so an uncaught error has nowhere to go). No "open with
      // another app" fallback is offered: the download itself failed, so no
      // application could open this file either.
      if (!mounted) return;
      final message = e is SftpStatusError
          ? 'Cannot open ${widget.entry.name}: the server refused to read it '
                '(special file, broken link, or no permission).'
          : 'Cannot open ${widget.entry.name}: $e';
      AppSnack.error(context, message);
      Navigator.of(context).pop();
    }
  }

  /// Shown when downloaded content turns out to be binary: offer to hand the
  /// file to the OS default app instead, then close the editor either way.
  Future<void> _offerExternalOpen() async {
    final open = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Cannot edit in-app',
        body: Text(
          '"${widget.entry.name}" appears to be a binary file.\n'
          'Open it with an external application instead? Changes saved '
          'there are uploaded back automatically.',
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.primary,
            onPress: () => Navigator.pop(ctx, true),
            child: const Text('Open externally'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (open == true) {
      try {
        await context.read<ExternalEditService>().openExternal(
          widget.host,
          widget.entry,
        );
      } catch (e) {
        if (mounted) {
          AppSnack.error(context, 'Open externally failed: $e');
        }
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['type'] as String;
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) {
        _pushContentToEditor();
      }
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
    _controller!.runJavaScript('loadContent($escaped, "$lang")');
    if (widget.readOnly) {
      _controller!.runJavaScript('setReadOnly(true)');
    }
  }

  /// Save entry point shared by the AppBar button and Ctrl/Cmd+S: pulls the
  /// current content from whichever editor is active.
  Future<void> _saveCurrent() async {
    if (_saving) return;
    if (_useWebView) {
      final content = await _controller!.runJavaScriptReturningResult(
        'getContent()',
      );
      await _saveFile(decodeWebViewString(content));
    } else {
      await _saveFile(_textController.text);
    }
  }

  Future<void> _saveFile(String content) async {
    setState(() => _saving = true);
    try {
      final service = context.read<SftpTransferService>();
      // Reuse the download location; path_provider only as a fallback when
      // the initial download never completed.
      final tmpPath =
          _tmpPath ??
          safeLocalChild(
            (await getTemporaryDirectory()).path,
            widget.entry.name,
          );
      await File(tmpPath).writeAsString(content);
      await service.uploadFile(widget.host, tmpPath, widget.entry.path);
      if (mounted) {
        setState(() => _isDirty = false);
        showYsToast(
          context,
          'Saved',
          kind: YsToastKind.success,
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDiscardDialog() async {
    final discard = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Unsaved changes',
        body: Text('Discard changes and close?'),
        actions: [
          FButton(
            autofocus: true,
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.readOnly || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showDiscardDialog();
      },
      child: Scaffold(
        backgroundColor: YsColors.terminalSurface,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: !_ready
                  ? const Center(child: FCircularProgress())
                  : _useWebView
                  ? WebViewWidget(controller: _controller!)
                  : _buildFallbackEditor(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerButton(IconData icon, String tooltip, VoidCallback? onPress) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: FButton.icon(
        variant: FButtonVariant.ghost,
        size: FButtonSizeVariant.sm,
        semanticsLabel: tooltip,
        onPress: onPress,
        child: Icon(icon),
      ),
    );
  }

  /// Editor header replacing the Material AppBar: back, file name, then the
  /// read-only lock or the save button (with its saving spinner).
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s2),
      decoration: const BoxDecoration(
        color: YsColors.card,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            _headerButton(
              FLucideIcons.arrowLeft,
              'Back',
              () => Navigator.of(context).maybePop(),
            ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: Text(
              widget.entry.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
                fontSize: 14,
                color: YsColors.foreground,
              ),
            ),
          ),
          if (widget.readOnly)
            const Padding(
              padding: EdgeInsets.all(YsSpace.s3),
              child: Icon(
                FLucideIcons.lock,
                size: 16,
                color: YsColors.mutedForeground,
              ),
            )
          else ...[
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(YsSpace.s3),
                child: FCircularProgress(size: FCircularProgressSizeVariant.sm),
              ),
            _headerButton(
              FLucideIcons.save,
              'Save (Ctrl+S)',
              _saving ? null : _saveCurrent,
            ),
          ],
        ],
      ),
    );
  }

  /// Plain-Flutter editor for platforms without a webview implementation.
  Widget _buildFallbackEditor() {
    final field = TextField(
      controller: _textController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      autofocus: !widget.readOnly,
      readOnly: widget.readOnly,
      style: const TextStyle(
        fontFamily: kYsMonoFontFamily,
        fontFamilyFallback: kYsMonoFontFallback,
        fontSize: 13,
        color: Color(0xFFE7E5E4),
        height: 1.5,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
      ),
      onChanged: widget.readOnly
          ? null
          : (_) {
              if (!_isDirty) setState(() => _isDirty = true);
            },
    );
    if (widget.readOnly) return field;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveCurrent,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _saveCurrent,
      },
      child: field,
    );
  }
}

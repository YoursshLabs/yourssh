import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

class ScriptPluginPanelScreen extends StatefulWidget {
  final PluginPanelEntry panel;

  const ScriptPluginPanelScreen({super.key, required this.panel});

  @override
  State<ScriptPluginPanelScreen> createState() =>
      _ScriptPluginPanelScreenState();
}

class _ScriptPluginPanelScreenState extends State<ScriptPluginPanelScreen> {
  late final WebViewController _controller;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PluginBridge',
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loaded = true),
        onWebResourceError: (e) =>
            setState(() => _error = 'WebView error: ${e.description}'),
      ));

    _loadPanel();
  }

  Future<void> _loadPanel() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    final htmlPath =
        '$home/.yourssh/plugins/${widget.panel.pluginId}/${widget.panel.webviewEntry}';
    final file = File(htmlPath);
    if (!file.existsSync()) {
      setState(() => _error = 'Panel file not found:\n$htmlPath');
      return;
    }
    final html = await file.readAsString();
    await _controller.loadHtmlString(html);
  }

  void _onBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = json.decode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final id = msg['id'] as String?;
    Map<String, dynamic> result;
    try {
      final responseStr = await widget.panel.onMessage(msg);
      if (responseStr != null) {
        final decoded = json.decode(responseStr);
        result = decoded is Map<String, dynamic> ? decoded : {'type': 'ok'};
      } else {
        result = {'type': 'ok'};
      }
    } catch (e) {
      result = {'type': 'error', 'message': e.toString()};
    }
    if (id != null) result['id'] = id;

    if (!mounted) return;
    // Escape single quotes in JSON to prevent JS injection
    final encoded = json.encode(result).replaceAll("'", "\\'");
    await _controller.runJavaScript("window.pluginBridge.receive('$encoded')");
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_loaded)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

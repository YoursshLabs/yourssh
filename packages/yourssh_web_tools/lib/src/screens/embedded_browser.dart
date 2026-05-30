import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme.dart';

class EmbeddedBrowser extends StatefulWidget {
  final String? initialUrl;
  const EmbeddedBrowser({super.key, this.initialUrl});

  @override
  State<EmbeddedBrowser> createState() => _EmbeddedBrowserState();
}

class _EmbeddedBrowserState extends State<EmbeddedBrowser> {
  late final WebViewController _controller;
  late final TextEditingController _urlCtrl;
  final _urlFocusNode = FocusNode();
  bool _loading = false;

  static const _defaultUrl = 'https://www.google.com';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUrl ?? _defaultUrl;
    _urlCtrl = TextEditingController(text: initial);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() => _loading = true);
          if (!_urlFocusNode.hasFocus) _urlCtrl.text = url;
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() => _loading = false);
          if (!_urlFocusNode.hasFocus) _urlCtrl.text = url;
        },
      ))
      ..loadRequest(Uri.parse(initial));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _navigate(String raw) {
    var target = raw.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null || uri.host.isEmpty) {
      _controller.loadRequest(
        Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(raw.trim())}'),
      );
      return;
    }
    _urlCtrl.text = target;
    _controller.loadRequest(uri);
  }

  void _stop() => _controller.runJavaScript('window.stop();');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AddressBar(
          controller: _urlCtrl,
          focusNode: _urlFocusNode,
          loading: _loading,
          onNavigate: _navigate,
          onBack: () => _controller.goBack(),
          onForward: () => _controller.goForward(),
          onReload: () => _controller.reload(),
          onStop: _stop,
        ),
        const Divider(height: 1, color: WebToolsColors.border),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    );
  }
}

class _AddressBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final ValueChanged<String> onNavigate;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;

  const _AddressBar({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onNavigate,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: WebToolsColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _NavBtn(icon: Icons.arrow_back_ios_new, size: 14, onTap: onBack),
          const SizedBox(width: 4),
          _NavBtn(icon: Icons.arrow_forward_ios, size: 14, onTap: onForward),
          const SizedBox(width: 4),
          _NavBtn(
            icon: loading ? Icons.close : Icons.refresh,
            size: 16,
            onTap: loading ? onStop : onReload,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: WebToolsColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WebToolsColors.border),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  if (loading)
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: WebToolsColors.accent),
                    )
                  else
                    const Icon(Icons.lock_outline, size: 12,
                        color: WebToolsColors.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                          color: WebToolsColors.textPrimary, fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                      onSubmitted: onNavigate,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.size, required this.onTap});

  @override
  State<_NavBtn> createState() => _NavBtnState();
}

class _NavBtnState extends State<_NavBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _hovered ? WebToolsColors.cardHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(widget.icon, size: widget.size,
              color: _hovered ? WebToolsColors.textPrimary : WebToolsColors.textSecondary),
        ),
      ),
    );
  }
}

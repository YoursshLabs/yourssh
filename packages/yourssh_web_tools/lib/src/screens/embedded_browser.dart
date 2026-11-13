import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../widgets/wt_widgets.dart';

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
  static const _allowedSchemes = {'http', 'https'};

  @override
  void initState() {
    super.initState();
    final initial = _coerceToSafeUrl(widget.initialUrl ?? _defaultUrl);
    _urlCtrl = TextEditingController(text: initial);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri != null && _allowedSchemes.contains(uri.scheme)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
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

  /// Coerces arbitrary input to an http(s) URL. Anything that parses to a
  /// non-http(s) scheme (`javascript:`, `file:`, `data:`, `chrome://`) is
  /// rewritten to a Google search so it can't reach the WebView raw.
  static String _coerceToSafeUrl(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && _allowedSchemes.contains(uri.scheme) && uri.host.isNotEmpty) {
      return trimmed;
    }
    if (!trimmed.contains('://') && trimmed.contains('.')) {
      final candidate = Uri.tryParse('https://$trimmed');
      if (candidate != null && candidate.host.isNotEmpty) return 'https://$trimmed';
    }
    return 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _navigate(String raw) {
    final target = _coerceToSafeUrl(raw);
    _urlCtrl.text = target;
    _controller.loadRequest(Uri.parse(target));
  }

  void _stop() => _controller.runJavaScript('window.stop();');

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: Column(
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
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
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
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s3,
        vertical: YsSpace.s2,
      ),
      child: Row(
        children: [
          WtIconButton(
            icon: FLucideIcons.arrowLeft,
            tooltip: 'Back',
            onPress: onBack,
          ),
          const SizedBox(width: YsSpace.s1),
          WtIconButton(
            icon: FLucideIcons.arrowRight,
            tooltip: 'Forward',
            onPress: onForward,
          ),
          const SizedBox(width: YsSpace.s1),
          WtIconButton(
            icon: loading ? FLucideIcons.x : FLucideIcons.refreshCw,
            tooltip: loading ? 'Stop' : 'Reload',
            onPress: loading ? onStop : onReload,
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: WtField(
              key: const ValueKey('browser-url'),
              controller: controller,
              focusNode: focusNode,
              mono: false,
              prefixIcon: loading ? FLucideIcons.loader : FLucideIcons.lock,
              onSubmit: onNavigate,
            ),
          ),
        ],
      ),
    );
  }
}

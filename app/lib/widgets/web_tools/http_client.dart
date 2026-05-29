import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

class HttpClientTool extends StatefulWidget {
  const HttpClientTool({super.key});

  @override
  State<HttpClientTool> createState() => _HttpClientToolState();
}

class _HttpClientToolState extends State<HttpClientTool> {
  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  String _method = 'GET';
  final _urlCtrl = TextEditingController(text: 'https://');
  final _headersCtrl = TextEditingController(text: 'Content-Type: application/json');
  final _bodyCtrl = TextEditingController();

  bool _loading = false;
  _HttpResponse? _response;

  bool get _hasBody => ['POST', 'PUT', 'PATCH'].contains(_method);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _parseHeaders(String raw) {
    final result = <String, String>{};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  Future<void> _send() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _loading = true;
      _response = null;
    });

    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.openUrl(_method, uri);
      final headers = _parseHeaders(_headersCtrl.text);
      headers.forEach(request.headers.set);

      if (_hasBody && _bodyCtrl.text.isNotEmpty) {
        final bodyBytes = utf8.encode(_bodyCtrl.text);
        request.contentLength = bodyBytes.length;
        request.add(bodyBytes);
      }

      final response = await request.close();
      final bodyRaw = await response.transform(utf8.decoder).join();
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      String prettyBody = bodyRaw;
      try {
        final decoded = jsonDecode(bodyRaw);
        prettyBody = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _response = _HttpResponse(
          statusCode: response.statusCode,
          reasonPhrase: response.reasonPhrase,
          headers: responseHeaders,
          body: prettyBody,
        );
      });
      client.close();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _response = _HttpResponse(
          statusCode: 0,
          reasonPhrase: 'Error',
          headers: {},
          body: e.toString(),
          isError: true,
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RequestBar(
          method: _method,
          methods: _methods,
          urlCtrl: _urlCtrl,
          loading: _loading,
          onMethodChanged: (m) => setState(() => _method = m),
          onSend: _send,
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _RequestPanel(
                  headersCtrl: _headersCtrl,
                  bodyCtrl: _bodyCtrl,
                  hasBody: _hasBody,
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Expanded(
                flex: 3,
                child: _ResponsePanel(response: _response, loading: _loading),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HttpResponse {
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String body;
  final bool isError;

  const _HttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    this.isError = false,
  });
}

class _RequestBar extends StatelessWidget {
  final String method;
  final List<String> methods;
  final TextEditingController urlCtrl;
  final bool loading;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onSend;

  const _RequestBar({
    required this.method,
    required this.methods,
    required this.urlCtrl,
    required this.loading,
    required this.onMethodChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButton<String>(
              value: method,
              underline: const SizedBox(),
              dropdownColor: AppColors.card,
              style: const TextStyle(
                  color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
              items: methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (m) {
                if (m != null) onMethodChanged(m);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: urlCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  hintText: 'https://api.example.com/endpoint',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(loading: loading, onSend: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onSend;
  const _SendButton({required this.loading, required this.onSend});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onSend,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered && !widget.loading ? AppColors.accentDim : AppColors.accent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Center(
                  child: Text('Send',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }
}

class _RequestPanel extends StatefulWidget {
  final TextEditingController headersCtrl;
  final TextEditingController bodyCtrl;
  final bool hasBody;
  const _RequestPanel(
      {required this.headersCtrl, required this.bodyCtrl, required this.hasBody});

  @override
  State<_RequestPanel> createState() => _RequestPanelState();
}

class _RequestPanelState extends State<_RequestPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: AppColors.sidebar,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.accent,
            labelStyle: const TextStyle(fontSize: 12),
            tabs: const [Tab(text: 'Headers'), Tab(text: 'Body')],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _CodeArea(controller: widget.headersCtrl, hint: 'Key: Value'),
              _CodeArea(
                controller: widget.bodyCtrl,
                hint: widget.hasBody
                    ? '{ "key": "value" }'
                    : 'Body not applicable for this method',
                enabled: widget.hasBody,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CodeArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;

  const _CodeArea({required this.controller, required this.hint, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: null,
        expands: true,
        style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ),
    );
  }
}

class _ResponsePanel extends StatefulWidget {
  final _HttpResponse? response;
  final bool loading;
  const _ResponsePanel({required this.response, required this.loading});

  @override
  State<_ResponsePanel> createState() => _ResponsePanelState();
}

class _ResponsePanelState extends State<_ResponsePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Color get _statusColor {
    final code = widget.response?.statusCode ?? 0;
    if (widget.response?.isError == true) return AppColors.red;
    if (code >= 200 && code < 300) return AppColors.accent;
    if (code >= 400) return AppColors.red;
    if (code >= 300) return AppColors.orange;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (widget.response == null) {
      return const Center(
        child: Text('Send a request to see the response',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      );
    }

    final r = widget.response!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: AppColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  r.statusCode == 0 ? 'Error' : '${r.statusCode} ${r.reasonPhrase}',
                  style: TextStyle(
                      color: _statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                color: AppColors.textSecondary,
                tooltip: 'Copy body',
                onPressed: () => Clipboard.setData(ClipboardData(text: r.body)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          labelStyle: const TextStyle(fontSize: 12),
          tabs: const [Tab(text: 'Body'), Tab(text: 'Headers')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ResponseBody(body: r.body),
              _ResponseHeaders(headers: r.headers),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResponseBody extends StatelessWidget {
  final String body;
  const _ResponseBody({required this.body});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        body,
        style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }
}

class _ResponseHeaders extends StatelessWidget {
  final Map<String, String> headers;
  const _ResponseHeaders({required this.headers});

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) {
      return const Center(
          child: Text('No headers',
              style: TextStyle(color: AppColors.textTertiary)));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: headers.entries
          .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: SelectableText(e.value,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

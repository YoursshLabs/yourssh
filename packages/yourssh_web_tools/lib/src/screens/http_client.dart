import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

@visibleForTesting
Map<String, String> parseHeaders(String raw) {
  final result = <String, String>{};
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
  }
  return result;
}

// ─── Models ──────────────────────────────────────────────────────────────────

class _KVPair {
  String key;
  String value;
  bool enabled;
  _KVPair(this.key, this.value, {this.enabled = true});
}

enum _AuthType { none, bearer, basic, apiKey }

enum _BodyType { none, raw, urlEncoded }

class _HistoryItem {
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  const _HistoryItem({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
  });
}

class _HttpResponse {
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String body;
  final bool isError;
  final int durationMs;
  final int sizeBytes;
  const _HttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    this.isError = false,
    required this.durationMs,
    required this.sizeBytes,
  });
}

// ─── Main Widget ─────────────────────────────────────────────────────────────

class HttpClientTool extends StatefulWidget {
  const HttpClientTool({super.key});

  @override
  State<HttpClientTool> createState() => _HttpClientToolState();
}

class _HttpClientToolState extends State<HttpClientTool> {
  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

  String _method = 'GET';
  final _urlCtrl = TextEditingController(text: 'https://');
  bool _syncingUrl = false;

  List<_KVPair> _params = [_KVPair('', '')];

  _AuthType _authType = _AuthType.none;
  final _bearerCtrl = TextEditingController();
  final _basicUserCtrl = TextEditingController();
  final _basicPassCtrl = TextEditingController();
  final _apiKeyNameCtrl = TextEditingController(text: 'X-API-Key');
  final _apiKeyValueCtrl = TextEditingController();
  bool _apiKeyInHeader = true;

  List<_KVPair> _headers = [
    _KVPair('Content-Type', 'application/json'),
    _KVPair('', ''),
  ];

  _BodyType _bodyType = _BodyType.raw;
  final _bodyCtrl = TextEditingController();
  List<_KVPair> _formPairs = [_KVPair('', '')];

  bool _loading = false;
  _HttpResponse? _response;

  final List<_HistoryItem> _history = [];
  bool _showHistory = false;

  bool get _hasBody => ['POST', 'PUT', 'PATCH'].contains(_method);

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlCtrl
      ..removeListener(_onUrlChanged)
      ..dispose();
    _bearerCtrl.dispose();
    _basicUserCtrl.dispose();
    _basicPassCtrl.dispose();
    _apiKeyNameCtrl.dispose();
    _apiKeyValueCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    if (_syncingUrl) return;
    _syncingUrl = true;
    try {
      final uri = Uri.tryParse(_urlCtrl.text);
      if (uri == null) return;
      final parsed = uri.queryParameters;
      if (parsed.isEmpty) {
        if (_params.any((p) => p.key.isNotEmpty)) {
          setState(() => _params = [_KVPair('', '')]);
        }
        return;
      }
      final newParams = parsed.entries.map((e) => _KVPair(e.key, e.value)).toList()
        ..add(_KVPair('', ''));
      setState(() => _params = newParams);
    } finally {
      _syncingUrl = false;
    }
  }

  void _updateUrlFromParams() {
    if (_syncingUrl) return;
    _syncingUrl = true;
    try {
      final url = _urlCtrl.text;
      final base = url.contains('?') ? url.substring(0, url.indexOf('?')) : url;
      final query = _params
          .where((p) => p.enabled && p.key.isNotEmpty)
          .map((p) =>
              '${Uri.encodeQueryComponent(p.key)}=${Uri.encodeQueryComponent(p.value)}')
          .join('&');
      final newUrl = query.isEmpty ? base : '$base?$query';
      if (newUrl != _urlCtrl.text) {
        _urlCtrl.value = _urlCtrl.value.copyWith(text: newUrl);
      }
    } finally {
      _syncingUrl = false;
    }
  }

  Map<String, String> _buildHeaders() {
    final result = <String, String>{};
    for (final kv in _headers) {
      if (kv.enabled && kv.key.isNotEmpty) result[kv.key] = kv.value;
    }
    switch (_authType) {
      case _AuthType.bearer:
        if (_bearerCtrl.text.isNotEmpty) {
          result['Authorization'] = 'Bearer ${_bearerCtrl.text}';
        }
      case _AuthType.basic:
        final encoded =
            base64.encode(utf8.encode('${_basicUserCtrl.text}:${_basicPassCtrl.text}'));
        result['Authorization'] = 'Basic $encoded';
      case _AuthType.apiKey:
        if (_apiKeyInHeader && _apiKeyNameCtrl.text.isNotEmpty) {
          result[_apiKeyNameCtrl.text] = _apiKeyValueCtrl.text;
        }
      case _AuthType.none:
        break;
    }
    return result;
  }

  String _buildFinalUrl() {
    final url = _urlCtrl.text.trim();
    if (_authType == _AuthType.apiKey &&
        !_apiKeyInHeader &&
        _apiKeyNameCtrl.text.isNotEmpty) {
      final base = url.contains('?') ? url.substring(0, url.indexOf('?')) : url;
      final existing = url.contains('?') ? url.substring(url.indexOf('?') + 1) : '';
      final param =
          '${Uri.encodeQueryComponent(_apiKeyNameCtrl.text)}=${Uri.encodeQueryComponent(_apiKeyValueCtrl.text)}';
      return '$base?${existing.isEmpty ? param : '$existing&$param'}';
    }
    return url;
  }

  Future<void> _send() async {
    final rawUrl = _urlCtrl.text.trim();
    if (rawUrl.isEmpty || rawUrl == 'https://') return;

    setState(() {
      _loading = true;
      _response = null;
    });
    final sw = Stopwatch()..start();

    try {
      final uri = Uri.parse(_buildFinalUrl());
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client.openUrl(_method, uri);
        _buildHeaders().forEach(req.headers.set);

        if (_hasBody) {
          List<int>? bytes;
          if (_bodyType == _BodyType.raw && _bodyCtrl.text.isNotEmpty) {
            bytes = utf8.encode(_bodyCtrl.text);
          } else if (_bodyType == _BodyType.urlEncoded) {
            final pairs = _formPairs.where((p) => p.enabled && p.key.isNotEmpty);
            final encoded = pairs
                .map((p) =>
                    '${Uri.encodeQueryComponent(p.key)}=${Uri.encodeQueryComponent(p.value)}')
                .join('&');
            if (encoded.isNotEmpty) {
              bytes = utf8.encode(encoded);
              req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
            }
          }
          if (bytes != null) {
            req.contentLength = bytes.length;
            req.add(bytes);
          }
        }

        final resp = await req.close();
        sw.stop();
        final bodyRaw = await resp.transform(utf8.decoder).join();
        final sizeBytes = utf8.encode(bodyRaw).length;

        final respHeaders = <String, String>{};
        resp.headers.forEach((k, v) => respHeaders[k] = v.join(', '));

        String prettyBody = bodyRaw;
        try {
          prettyBody = const JsonEncoder.withIndent('  ').convert(jsonDecode(bodyRaw));
        } catch (_) {}

        if (!mounted) return;
        final response = _HttpResponse(
          statusCode: resp.statusCode,
          reasonPhrase: resp.reasonPhrase,
          headers: respHeaders,
          body: prettyBody,
          durationMs: sw.elapsedMilliseconds,
          sizeBytes: sizeBytes,
        );
        setState(() {
          _response = response;
          _history.insert(
            0,
            _HistoryItem(
              method: _method,
              url: _buildFinalUrl(),
              statusCode: resp.statusCode,
              durationMs: sw.elapsedMilliseconds,
            ),
          );
          if (_history.length > 30) _history.removeLast();
        });
      } finally {
        client.close();
      }
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _response = _HttpResponse(
          statusCode: 0,
          reasonPhrase: 'Error',
          headers: {},
          body: e.toString(),
          isError: true,
          durationMs: sw.elapsedMilliseconds,
          sizeBytes: 0,
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadFromHistory(_HistoryItem item) {
    setState(() {
      _method = item.method;
      _urlCtrl.text = item.url;
      _showHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _RequestBar(
              method: _method,
              methods: _methods,
              urlCtrl: _urlCtrl,
              loading: _loading,
              historyCount: _history.length,
              onMethodChanged: (m) => setState(() => _method = m),
              onSend: _send,
              onToggleHistory: () => setState(() => _showHistory = !_showHistory),
            ),
            const Divider(height: 1, color: WebToolsColors.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _RequestPanel(
                      params: _params,
                      headers: _headers,
                      authType: _authType,
                      bearerCtrl: _bearerCtrl,
                      basicUserCtrl: _basicUserCtrl,
                      basicPassCtrl: _basicPassCtrl,
                      apiKeyNameCtrl: _apiKeyNameCtrl,
                      apiKeyValueCtrl: _apiKeyValueCtrl,
                      apiKeyInHeader: _apiKeyInHeader,
                      bodyType: _bodyType,
                      bodyCtrl: _bodyCtrl,
                      formPairs: _formPairs,
                      hasBody: _hasBody,
                      onParamsChanged: (p) {
                        setState(() => _params = p);
                        _updateUrlFromParams();
                      },
                      onHeadersChanged: (h) => setState(() => _headers = h),
                      onAuthTypeChanged: (t) => setState(() => _authType = t),
                      onApiKeyInHeaderChanged: (v) =>
                          setState(() => _apiKeyInHeader = v),
                      onBodyTypeChanged: (t) => setState(() => _bodyType = t),
                      onFormPairsChanged: (p) => setState(() => _formPairs = p),
                    ),
                  ),
                  Container(width: 1, color: WebToolsColors.border),
                  Expanded(
                    flex: 3,
                    child: _ResponsePanel(response: _response, loading: _loading),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_showHistory)
          Positioned(
            top: 53,
            left: 0,
            bottom: 0,
            width: 340,
            child: _HistoryPanel(
              history: _history,
              onSelect: _loadFromHistory,
              onClose: () => setState(() => _showHistory = false),
            ),
          ),
      ],
    );
  }
}

// ─── Request Bar ─────────────────────────────────────────────────────────────

class _RequestBar extends StatelessWidget {
  final String method;
  final List<String> methods;
  final TextEditingController urlCtrl;
  final bool loading;
  final int historyCount;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onSend;
  final VoidCallback onToggleHistory;

  const _RequestBar({
    required this.method,
    required this.methods,
    required this.urlCtrl,
    required this.loading,
    required this.historyCount,
    required this.onMethodChanged,
    required this.onSend,
    required this.onToggleHistory,
  });

  Color _methodColor(String m) => switch (m) {
        'GET' => const Color(0xFF61AFFE),
        'POST' => const Color(0xFF49CC90),
        'PUT' => const Color(0xFFFCA130),
        'PATCH' => const Color(0xFF50E3C2),
        'DELETE' => const Color(0xFFF93E3E),
        _ => WebToolsColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: WebToolsColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: WebToolsColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: WebToolsColors.border),
            ),
            child: DropdownButton<String>(
              value: method,
              underline: const SizedBox(),
              dropdownColor: WebToolsColors.card,
              style: TextStyle(
                  color: _methodColor(method),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              items: methods
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child:
                            Text(m, style: TextStyle(color: _methodColor(m))),
                      ))
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
                color: WebToolsColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: WebToolsColors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                controller: urlCtrl,
                style:
                    const TextStyle(color: WebToolsColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  hintText: 'https://api.example.com/endpoint',
                  hintStyle:
                      TextStyle(color: WebToolsColors.textTertiary, fontSize: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.history, size: 18),
                color: WebToolsColors.textSecondary,
                tooltip: 'Request history',
                onPressed: onToggleHistory,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              if (historyCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: WebToolsColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      historyCount > 9 ? '9+' : '$historyCount',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
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
            color: _hovered && !widget.loading
                ? WebToolsColors.accentDim
                : WebToolsColors.accent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  ))
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

// ─── Request Panel ────────────────────────────────────────────────────────────

class _RequestPanel extends StatefulWidget {
  final List<_KVPair> params;
  final List<_KVPair> headers;
  final _AuthType authType;
  final TextEditingController bearerCtrl;
  final TextEditingController basicUserCtrl;
  final TextEditingController basicPassCtrl;
  final TextEditingController apiKeyNameCtrl;
  final TextEditingController apiKeyValueCtrl;
  final bool apiKeyInHeader;
  final _BodyType bodyType;
  final TextEditingController bodyCtrl;
  final List<_KVPair> formPairs;
  final bool hasBody;
  final ValueChanged<List<_KVPair>> onParamsChanged;
  final ValueChanged<List<_KVPair>> onHeadersChanged;
  final ValueChanged<_AuthType> onAuthTypeChanged;
  final ValueChanged<bool> onApiKeyInHeaderChanged;
  final ValueChanged<_BodyType> onBodyTypeChanged;
  final ValueChanged<List<_KVPair>> onFormPairsChanged;

  const _RequestPanel({
    required this.params,
    required this.headers,
    required this.authType,
    required this.bearerCtrl,
    required this.basicUserCtrl,
    required this.basicPassCtrl,
    required this.apiKeyNameCtrl,
    required this.apiKeyValueCtrl,
    required this.apiKeyInHeader,
    required this.bodyType,
    required this.bodyCtrl,
    required this.formPairs,
    required this.hasBody,
    required this.onParamsChanged,
    required this.onHeadersChanged,
    required this.onAuthTypeChanged,
    required this.onApiKeyInHeaderChanged,
    required this.onBodyTypeChanged,
    required this.onFormPairsChanged,
  });

  @override
  State<_RequestPanel> createState() => _RequestPanelState();
}

class _RequestPanelState extends State<_RequestPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int get _activeParamsCount =>
      widget.params.where((p) => p.enabled && p.key.isNotEmpty).length;

  int get _activeHeadersCount =>
      widget.headers.where((h) => h.enabled && h.key.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: WebToolsColors.sidebar,
          child: TabBar(
            controller: _tabs,
            labelColor: WebToolsColors.accent,
            unselectedLabelColor: WebToolsColors.textSecondary,
            indicatorColor: WebToolsColors.accent,
            labelStyle: const TextStyle(fontSize: 11),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                  text:
                      'Params${_activeParamsCount > 0 ? ' ($_activeParamsCount)' : ''}'),
              Tab(
                  text:
                      'Auth${widget.authType != _AuthType.none ? ' •' : ''}'),
              Tab(
                  text:
                      'Headers${_activeHeadersCount > 0 ? ' ($_activeHeadersCount)' : ''}'),
              const Tab(text: 'Body'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _KVEditor(
                  pairs: widget.params,
                  keyHint: 'Key',
                  valueHint: 'Value',
                  onChange: widget.onParamsChanged),
              _AuthPanel(
                authType: widget.authType,
                bearerCtrl: widget.bearerCtrl,
                basicUserCtrl: widget.basicUserCtrl,
                basicPassCtrl: widget.basicPassCtrl,
                apiKeyNameCtrl: widget.apiKeyNameCtrl,
                apiKeyValueCtrl: widget.apiKeyValueCtrl,
                apiKeyInHeader: widget.apiKeyInHeader,
                onAuthTypeChanged: widget.onAuthTypeChanged,
                onApiKeyInHeaderChanged: widget.onApiKeyInHeaderChanged,
              ),
              _KVEditor(
                  pairs: widget.headers,
                  keyHint: 'Header',
                  valueHint: 'Value',
                  onChange: widget.onHeadersChanged),
              _BodyPanel(
                bodyType: widget.bodyType,
                bodyCtrl: widget.bodyCtrl,
                formPairs: widget.formPairs,
                hasBody: widget.hasBody,
                onBodyTypeChanged: widget.onBodyTypeChanged,
                onFormPairsChanged: widget.onFormPairsChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── KV Editor ───────────────────────────────────────────────────────────────

class _KVEditor extends StatelessWidget {
  final List<_KVPair> pairs;
  final String keyHint;
  final String valueHint;
  final ValueChanged<List<_KVPair>> onChange;

  const _KVEditor({
    required this.pairs,
    required this.keyHint,
    required this.valueHint,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebToolsColors.bg,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: pairs.length,
        itemBuilder: (_, i) {
          return _KVRow(
            pair: pairs[i],
            keyHint: keyHint,
            valueHint: valueHint,
            onChanged: (p) {
              final updated = List<_KVPair>.from(pairs);
              updated[i] = p;
              if (i == pairs.length - 1 && p.key.isNotEmpty) {
                updated.add(_KVPair('', ''));
              }
              onChange(updated);
            },
            onRemove: pairs.length > 1
                ? () {
                    final updated = List<_KVPair>.from(pairs)..removeAt(i);
                    onChange(updated);
                  }
                : null,
          );
        },
      ),
    );
  }
}

class _KVRow extends StatefulWidget {
  final _KVPair pair;
  final String keyHint;
  final String valueHint;
  final ValueChanged<_KVPair> onChanged;
  final VoidCallback? onRemove;

  const _KVRow({
    required this.pair,
    required this.keyHint,
    required this.valueHint,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<_KVRow> createState() => _KVRowState();
}

class _KVRowState extends State<_KVRow> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;
  bool _keyFocused = false;
  bool _valFocused = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.pair.key);
    _valCtrl = TextEditingController(text: widget.pair.value);
  }

  @override
  void didUpdateWidget(_KVRow old) {
    super.didUpdateWidget(old);
    if (!_keyFocused &&
        old.pair.key != widget.pair.key &&
        _keyCtrl.text != widget.pair.key) {
      _keyCtrl.text = widget.pair.key;
    }
    if (!_valFocused &&
        old.pair.value != widget.pair.value &&
        _valCtrl.text != widget.pair.value) {
      _valCtrl.text = widget.pair.value;
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged(
      _KVPair(_keyCtrl.text, _valCtrl.text, enabled: widget.pair.enabled));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Checkbox(
              value: widget.pair.enabled,
              onChanged: (_) => widget.onChanged(_KVPair(
                  widget.pair.key, widget.pair.value,
                  enabled: !widget.pair.enabled)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: WebToolsColors.textTertiary),
              activeColor: WebToolsColors.accent,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
              child: _cell(_keyCtrl, widget.keyHint,
                  onFocus: (f) => _keyFocused = f)),
          const SizedBox(width: 4),
          Expanded(
              child: _cell(_valCtrl, widget.valueHint,
                  onFocus: (f) => _valFocused = f)),
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            child: widget.onRemove != null
                ? GestureDetector(
                    onTap: widget.onRemove,
                    child: const Icon(Icons.close,
                        size: 13, color: WebToolsColors.textTertiary),
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _cell(TextEditingController ctrl, String hint,
      {required ValueChanged<bool> onFocus}) {
    return Focus(
      onFocusChange: onFocus,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: WebToolsColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: WebToolsColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: TextField(
          controller: ctrl,
          style: const TextStyle(
              color: WebToolsColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 5),
            border: InputBorder.none,
            hintText: hint,
            hintStyle:
                const TextStyle(color: WebToolsColors.textTertiary, fontSize: 12),
          ),
          onChanged: (_) => _notify(),
        ),
      ),
    );
  }
}

// ─── Auth Panel ───────────────────────────────────────────────────────────────

class _AuthPanel extends StatelessWidget {
  final _AuthType authType;
  final TextEditingController bearerCtrl;
  final TextEditingController basicUserCtrl;
  final TextEditingController basicPassCtrl;
  final TextEditingController apiKeyNameCtrl;
  final TextEditingController apiKeyValueCtrl;
  final bool apiKeyInHeader;
  final ValueChanged<_AuthType> onAuthTypeChanged;
  final ValueChanged<bool> onApiKeyInHeaderChanged;

  const _AuthPanel({
    required this.authType,
    required this.bearerCtrl,
    required this.basicUserCtrl,
    required this.basicPassCtrl,
    required this.apiKeyNameCtrl,
    required this.apiKeyValueCtrl,
    required this.apiKeyInHeader,
    required this.onAuthTypeChanged,
    required this.onApiKeyInHeaderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Auth Type',
                  style: TextStyle(
                      color: WebToolsColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: WebToolsColors.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: WebToolsColors.border),
                ),
                child: DropdownButton<_AuthType>(
                  value: authType,
                  underline: const SizedBox(),
                  dropdownColor: WebToolsColors.card,
                  style: const TextStyle(
                      color: WebToolsColors.textPrimary, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                        value: _AuthType.none, child: Text('No Auth')),
                    DropdownMenuItem(
                        value: _AuthType.bearer,
                        child: Text('Bearer Token')),
                    DropdownMenuItem(
                        value: _AuthType.basic, child: Text('Basic Auth')),
                    DropdownMenuItem(
                        value: _AuthType.apiKey, child: Text('API Key')),
                  ],
                  onChanged: (t) {
                    if (t != null) onAuthTypeChanged(t);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (authType == _AuthType.none)
            const Text('Request will be sent without authentication.',
                style:
                    TextStyle(color: WebToolsColors.textTertiary, fontSize: 12)),
          if (authType == _AuthType.bearer) ...[
            const _FieldLabel('Token'),
            const SizedBox(height: 6),
            _AuthField(controller: bearerCtrl, hint: 'Enter Bearer token'),
          ],
          if (authType == _AuthType.basic) ...[
            const _FieldLabel('Username'),
            const SizedBox(height: 6),
            _AuthField(controller: basicUserCtrl, hint: 'Username'),
            const SizedBox(height: 10),
            const _FieldLabel('Password'),
            const SizedBox(height: 6),
            _AuthField(
                controller: basicPassCtrl,
                hint: 'Password',
                obscure: true),
          ],
          if (authType == _AuthType.apiKey) ...[
            const _FieldLabel('Key Name'),
            const SizedBox(height: 6),
            _AuthField(controller: apiKeyNameCtrl, hint: 'e.g. X-API-Key'),
            const SizedBox(height: 10),
            const _FieldLabel('Key Value'),
            const SizedBox(height: 6),
            _AuthField(controller: apiKeyValueCtrl, hint: 'API key value'),
            const SizedBox(height: 10),
            Row(
              children: [
                const _FieldLabel('Add to'),
                const SizedBox(width: 12),
                _Chip(
                    label: 'Header',
                    selected: apiKeyInHeader,
                    onTap: () => onApiKeyInHeaderChanged(true)),
                const SizedBox(width: 6),
                _Chip(
                    label: 'Query Param',
                    selected: !apiKeyInHeader,
                    onTap: () => onApiKeyInHeaderChanged(false)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: WebToolsColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500));
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const _AuthField(
      {required this.controller, required this.hint, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: WebToolsColors.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: WebToolsColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(
            color: WebToolsColors.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace'),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
          hintText: hint,
          hintStyle:
              const TextStyle(color: WebToolsColors.textTertiary, fontSize: 12),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? WebToolsColors.accent.withValues(alpha: 0.15)
              : WebToolsColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: selected
                  ? WebToolsColors.accent.withValues(alpha: 0.4)
                  : WebToolsColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? WebToolsColors.accent : WebToolsColors.textSecondary,
                fontSize: 11)),
      ),
    );
  }
}

// ─── Body Panel ───────────────────────────────────────────────────────────────

class _BodyPanel extends StatelessWidget {
  final _BodyType bodyType;
  final TextEditingController bodyCtrl;
  final List<_KVPair> formPairs;
  final bool hasBody;
  final ValueChanged<_BodyType> onBodyTypeChanged;
  final ValueChanged<List<_KVPair>> onFormPairsChanged;

  const _BodyPanel({
    required this.bodyType,
    required this.bodyCtrl,
    required this.formPairs,
    required this.hasBody,
    required this.onBodyTypeChanged,
    required this.onFormPairsChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasBody) {
      return const Center(
        child: Text('Body not applicable for this method',
            style: TextStyle(color: WebToolsColors.textTertiary, fontSize: 12)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: WebToolsColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _Chip(
                  label: 'JSON',
                  selected: bodyType == _BodyType.raw,
                  onTap: () => onBodyTypeChanged(_BodyType.raw)),
              const SizedBox(width: 6),
              _Chip(
                  label: 'URL Encoded',
                  selected: bodyType == _BodyType.urlEncoded,
                  onTap: () => onBodyTypeChanged(_BodyType.urlEncoded)),
              const SizedBox(width: 6),
              _Chip(
                  label: 'None',
                  selected: bodyType == _BodyType.none,
                  onTap: () => onBodyTypeChanged(_BodyType.none)),
            ],
          ),
        ),
        Expanded(
          child: switch (bodyType) {
            _BodyType.raw =>
              _CodeArea(controller: bodyCtrl, hint: '{ "key": "value" }'),
            _BodyType.urlEncoded => _KVEditor(
                pairs: formPairs,
                keyHint: 'Key',
                valueHint: 'Value',
                onChange: onFormPairsChanged),
            _BodyType.none => const Center(
                child: Text('No body',
                    style: TextStyle(
                        color: WebToolsColors.textTertiary, fontSize: 12))),
          },
        ),
      ],
    );
  }
}

class _CodeArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _CodeArea({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebToolsColors.bg,
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        style: const TextStyle(
            color: WebToolsColors.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace'),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle:
              const TextStyle(color: WebToolsColors.textTertiary, fontSize: 12),
        ),
      ),
    );
  }
}

// ─── Response Panel ───────────────────────────────────────────────────────────

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
    if (widget.response?.isError == true) return WebToolsColors.red;
    if (code >= 200 && code < 300) return WebToolsColors.accent;
    if (code >= 400) return WebToolsColors.red;
    if (code >= 300) return WebToolsColors.orange;
    return WebToolsColors.textSecondary;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
          child: CircularProgressIndicator(color: WebToolsColors.accent));
    }
    if (widget.response == null) {
      return const Center(
        child: Text('Send a request to see the response',
            style: TextStyle(color: WebToolsColors.textTertiary, fontSize: 13)),
      );
    }

    final r = widget.response!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: WebToolsColors.sidebar,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: _statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  r.statusCode == 0
                      ? 'Error'
                      : '${r.statusCode} ${r.reasonPhrase}',
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text('${r.durationMs} ms',
                  style: const TextStyle(
                      color: WebToolsColors.textSecondary, fontSize: 11)),
              const SizedBox(width: 8),
              Text(_formatSize(r.sizeBytes),
                  style: const TextStyle(
                      color: WebToolsColors.textSecondary, fontSize: 11)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                color: WebToolsColors.textSecondary,
                tooltip: 'Copy body',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: r.body)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: WebToolsColors.accent,
          unselectedLabelColor: WebToolsColors.textSecondary,
          indicatorColor: WebToolsColors.accent,
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
            color: WebToolsColors.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace'),
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
              style: TextStyle(color: WebToolsColors.textTertiary)));
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
                              color: WebToolsColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: SelectableText(e.value,
                          style: const TextStyle(
                              color: WebToolsColors.textPrimary,
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

// ─── History Panel ────────────────────────────────────────────────────────────

class _HistoryPanel extends StatelessWidget {
  final List<_HistoryItem> history;
  final ValueChanged<_HistoryItem> onSelect;
  final VoidCallback onClose;

  const _HistoryPanel(
      {required this.history, required this.onSelect, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: WebToolsColors.sidebar,
      child: Column(
        children: [
          Container(
            color: WebToolsColors.card,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Text('History',
                    style: TextStyle(
                        color: WebToolsColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: WebToolsColors.textSecondary,
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WebToolsColors.border),
          if (history.isEmpty)
            const Expanded(
                child: Center(
                    child: Text('No history yet',
                        style: TextStyle(
                            color: WebToolsColors.textTertiary, fontSize: 12))))
          else
            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: WebToolsColors.border),
                itemBuilder: (_, i) => _HistoryRow(
                    item: history[i], onTap: () => onSelect(history[i])),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final _HistoryItem item;
  final VoidCallback onTap;
  const _HistoryRow({required this.item, required this.onTap});

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hovered = false;

  Color _methodColor(String m) => switch (m) {
        'GET' => const Color(0xFF61AFFE),
        'POST' => const Color(0xFF49CC90),
        'PUT' => const Color(0xFFFCA130),
        'PATCH' => const Color(0xFF50E3C2),
        'DELETE' => const Color(0xFFF93E3E),
        _ => WebToolsColors.textSecondary,
      };

  Color _statusColor(int code) {
    if (code >= 200 && code < 300) return WebToolsColors.accent;
    if (code >= 400) return WebToolsColors.red;
    if (code >= 300) return WebToolsColors.orange;
    return WebToolsColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color:
              _hovered ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(item.method,
                    style: TextStyle(
                        color: _methodColor(item.method),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Text(item.url,
                    style: const TextStyle(
                        color: WebToolsColors.textPrimary, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(
                  item.statusCode == 0 ? 'ERR' : '${item.statusCode}',
                  style: TextStyle(
                      color: _statusColor(item.statusCode),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${item.durationMs}ms',
                  style: const TextStyle(
                      color: WebToolsColors.textTertiary, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

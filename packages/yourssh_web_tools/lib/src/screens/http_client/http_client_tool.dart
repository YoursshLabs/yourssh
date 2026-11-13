import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'history_panel.dart';
import 'models.dart';
import 'request_bar.dart';
import 'request_panel.dart';
import 'response_panel.dart';

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

  List<KvPair> _params = [KvPair('', '')];

  AuthType _authType = AuthType.none;
  final _bearerCtrl = TextEditingController();
  final _basicUserCtrl = TextEditingController();
  final _basicPassCtrl = TextEditingController();
  final _apiKeyNameCtrl = TextEditingController(text: 'X-API-Key');
  final _apiKeyValueCtrl = TextEditingController();
  bool _apiKeyInHeader = true;

  List<KvPair> _headers = [
    KvPair('Content-Type', 'application/json'),
    KvPair('', ''),
  ];

  BodyType _bodyType = BodyType.raw;
  final _bodyCtrl = TextEditingController();
  List<KvPair> _formPairs = [KvPair('', '')];

  bool _loading = false;
  HttpResponse? _response;

  final List<HistoryItem> _history = [];
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
          setState(() => _params = [KvPair('', '')]);
        }
        return;
      }
      final newParams = parsed.entries.map((e) => KvPair(e.key, e.value)).toList()
        ..add(KvPair('', ''));
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
      case AuthType.bearer:
        if (_bearerCtrl.text.isNotEmpty) {
          result['Authorization'] = 'Bearer ${_bearerCtrl.text}';
        }
      case AuthType.basic:
        final encoded =
            base64.encode(utf8.encode('${_basicUserCtrl.text}:${_basicPassCtrl.text}'));
        result['Authorization'] = 'Basic $encoded';
      case AuthType.apiKey:
        if (_apiKeyInHeader && _apiKeyNameCtrl.text.isNotEmpty) {
          result[_apiKeyNameCtrl.text] = _apiKeyValueCtrl.text;
        }
      case AuthType.none:
        break;
    }
    return result;
  }

  String _buildFinalUrl() {
    final url = _urlCtrl.text.trim();
    if (_authType == AuthType.apiKey &&
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

    const requestTimeout = Duration(seconds: 60);
    try {
      final uri = Uri.parse(_buildFinalUrl());
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client.openUrl(_method, uri);
        _buildHeaders().forEach(req.headers.set);

        if (_hasBody) {
          List<int>? bytes;
          if (_bodyType == BodyType.raw && _bodyCtrl.text.isNotEmpty) {
            bytes = utf8.encode(_bodyCtrl.text);
          } else if (_bodyType == BodyType.urlEncoded) {
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

        final resp = await req.close().timeout(requestTimeout);
        sw.stop();
        final bodyRaw = await resp.transform(utf8.decoder).join().timeout(requestTimeout);
        final sizeBytes = utf8.encode(bodyRaw).length;

        final respHeaders = <String, String>{};
        resp.headers.forEach((k, v) => respHeaders[k] = v.join(', '));

        String prettyBody = bodyRaw;
        try {
          prettyBody = const JsonEncoder.withIndent('  ').convert(jsonDecode(bodyRaw));
        } catch (_) {}

        if (!mounted) return;
        final response = HttpResponse(
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
            HistoryItem(
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
        _response = HttpResponse(
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

  void _loadFromHistory(HistoryItem item) {
    setState(() {
      _method = item.method;
      _urlCtrl.text = item.url;
      _showHistory = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: Column(
        children: [
          RequestBar(
            method: _method,
            methods: _methods,
            urlCtrl: _urlCtrl,
            loading: _loading,
            historyCount: _history.length,
            onMethodChanged: (m) => setState(() => _method = m),
            onSend: _send,
            onToggleHistory: () => setState(() => _showHistory = !_showHistory),
          ),
          Expanded(
            // The history slide-over sits below the request bar so its toggle
            // stays reachable.
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: RequestPanel(
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
                        onFormPairsChanged: (p) =>
                            setState(() => _formPairs = p),
                      ),
                    ),
                    const FDivider(axis: Axis.vertical),
                    Expanded(
                      flex: 3,
                      child: HttpResponsePanel(
                        response: _response,
                        loading: _loading,
                      ),
                    ),
                  ],
                ),
                if (_showHistory)
                  Positioned(
                    top: 0,
                    left: 0,
                    bottom: 0,
                    width: 340,
                    child: HttpHistoryPanel(
                      history: _history,
                      onSelect: _loadFromHistory,
                      onClose: () => setState(() => _showHistory = false),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

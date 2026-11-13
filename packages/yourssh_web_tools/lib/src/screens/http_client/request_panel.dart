import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'auth_panel.dart';
import 'body_panel.dart';
import 'kv_editor.dart';
import 'models.dart';

/// Params / Auth / Headers / Body tabs of the request.
class RequestPanel extends StatelessWidget {
  final List<KvPair> params;
  final List<KvPair> headers;
  final AuthType authType;
  final TextEditingController bearerCtrl;
  final TextEditingController basicUserCtrl;
  final TextEditingController basicPassCtrl;
  final TextEditingController apiKeyNameCtrl;
  final TextEditingController apiKeyValueCtrl;
  final bool apiKeyInHeader;
  final BodyType bodyType;
  final TextEditingController bodyCtrl;
  final List<KvPair> formPairs;
  final bool hasBody;
  final ValueChanged<List<KvPair>> onParamsChanged;
  final ValueChanged<List<KvPair>> onHeadersChanged;
  final ValueChanged<AuthType> onAuthTypeChanged;
  final ValueChanged<bool> onApiKeyInHeaderChanged;
  final ValueChanged<BodyType> onBodyTypeChanged;
  final ValueChanged<List<KvPair>> onFormPairsChanged;

  const RequestPanel({
    super.key,
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

  int get _activeParamsCount =>
      params.where((p) => p.enabled && p.key.isNotEmpty).length;

  int get _activeHeadersCount =>
      headers.where((h) => h.enabled && h.key.isNotEmpty).length;

  Widget _label(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

  @override
  Widget build(BuildContext context) {
    return FTabs(
      key: const ValueKey('http-request-tabs'),
      expands: true,
      scrollable: true,
      children: [
        FTabEntry(
          label: _label(
            'Params${_activeParamsCount > 0 ? ' ($_activeParamsCount)' : ''}',
          ),
          child: KvEditor(
            pairs: params,
            keyHint: 'Key',
            valueHint: 'Value',
            onChange: onParamsChanged,
          ),
        ),
        FTabEntry(
          label: _label('Auth${authType != AuthType.none ? ' •' : ''}'),
          child: AuthPanel(
            authType: authType,
            bearerCtrl: bearerCtrl,
            basicUserCtrl: basicUserCtrl,
            basicPassCtrl: basicPassCtrl,
            apiKeyNameCtrl: apiKeyNameCtrl,
            apiKeyValueCtrl: apiKeyValueCtrl,
            apiKeyInHeader: apiKeyInHeader,
            onAuthTypeChanged: onAuthTypeChanged,
            onApiKeyInHeaderChanged: onApiKeyInHeaderChanged,
          ),
        ),
        FTabEntry(
          label: _label(
            'Headers${_activeHeadersCount > 0 ? ' ($_activeHeadersCount)' : ''}',
          ),
          child: KvEditor(
            pairs: headers,
            keyHint: 'Header',
            valueHint: 'Value',
            onChange: onHeadersChanged,
          ),
        ),
        FTabEntry(
          label: _label('Body'),
          child: BodyPanel(
            bodyType: bodyType,
            bodyCtrl: bodyCtrl,
            formPairs: formPairs,
            hasBody: hasBody,
            onBodyTypeChanged: onBodyTypeChanged,
            onFormPairsChanged: onFormPairsChanged,
          ),
        ),
      ],
    );
  }
}

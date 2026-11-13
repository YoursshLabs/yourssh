import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'models.dart';

class AuthPanel extends StatelessWidget {
  final AuthType authType;
  final TextEditingController bearerCtrl;
  final TextEditingController basicUserCtrl;
  final TextEditingController basicPassCtrl;
  final TextEditingController apiKeyNameCtrl;
  final TextEditingController apiKeyValueCtrl;
  final bool apiKeyInHeader;
  final ValueChanged<AuthType> onAuthTypeChanged;
  final ValueChanged<bool> onApiKeyInHeaderChanged;

  const AuthPanel({
    super.key,
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

  static const _types = [
    (AuthType.none, 'No Auth'),
    (AuthType.bearer, 'Bearer Token'),
    (AuthType.basic, 'Basic Auth'),
    (AuthType.apiKey, 'API Key'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(YsSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FSelect<int>.rich(
              key: const ValueKey('http-auth-type'),
              size: .sm,
              label: const Text('Auth Type'),
              control: .lifted(
                value: _types.indexWhere((t) => t.$1 == authType),
                onChange: (i) {
                  if (i != null) onAuthTypeChanged(_types[i].$1);
                },
              ),
              format: (i) => _types[i].$2,
              children: [
                for (final (i, t) in _types.indexed)
                  FSelectItem<int>(title: Text(t.$2), value: i),
              ],
            ),
            const SizedBox(height: YsSpace.s4),
            if (authType == AuthType.none)
              const WtCaption('Request will be sent without authentication.'),
            if (authType == AuthType.bearer)
              _labeled(
                'Token',
                WtField(
                  key: const ValueKey('http-auth-bearer'),
                  controller: bearerCtrl,
                  hint: 'Enter Bearer token',
                ),
              ),
            if (authType == AuthType.basic) ...[
              _labeled(
                'Username',
                WtField(
                  key: const ValueKey('http-auth-basic-user'),
                  controller: basicUserCtrl,
                  hint: 'Username',
                ),
              ),
              const SizedBox(height: YsSpace.s3),
              _labeled(
                'Password',
                WtField(
                  key: const ValueKey('http-auth-basic-pass'),
                  controller: basicPassCtrl,
                  hint: 'Password',
                  obscure: true,
                ),
              ),
            ],
            if (authType == AuthType.apiKey) ...[
              _labeled(
                'Key Name',
                WtField(
                  key: const ValueKey('http-auth-key-name'),
                  controller: apiKeyNameCtrl,
                  hint: 'e.g. X-API-Key',
                ),
              ),
              const SizedBox(height: YsSpace.s3),
              _labeled(
                'Key Value',
                WtField(
                  key: const ValueKey('http-auth-key-value'),
                  controller: apiKeyValueCtrl,
                  hint: 'API key value',
                ),
              ),
              const SizedBox(height: YsSpace.s3),
              _labeled(
                'Add to',
                Row(
                  children: [
                    WtChip(
                      label: 'Header',
                      selected: apiKeyInHeader,
                      onTap: () => onApiKeyInHeaderChanged(true),
                    ),
                    const SizedBox(width: YsSpace.s2),
                    WtChip(
                      label: 'Query Param',
                      selected: !apiKeyInHeader,
                      onTap: () => onApiKeyInHeaderChanged(false),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: YsColors.mutedForeground,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: YsSpace.s1 + 2),
      child,
    ],
  );
}

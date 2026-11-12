import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/share_provider.dart';
import '../providers/sync_provider.dart';
import '../services/share_crypto.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class JoinShareDialog extends StatefulWidget {
  const JoinShareDialog({super.key});

  @override
  State<JoinShareDialog> createState() => _JoinShareDialogState();
}

class _JoinShareDialogState extends State<JoinShareDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _joining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join(BuildContext context) async {
    final code = ShareCrypto.normalizeCode(_controller.text);
    if (code == null) {
      setState(() => _error = 'Enter the full share code (XXXXXX-XXXXXXXXXXXXXXXX)');
      return;
    }

    final sync = context.read<SyncProvider>();
    if (!sync.isSupabaseConfigured) {
      setState(() => _error = 'Configure Supabase first (Settings → Sync)');
      return;
    }

    setState(() { _joining = true; _error = null; });
    try {
      await context.read<ShareProvider>().joinSession(
        code,
        sync.supabaseUrl,
        sync.supabaseAnonKey,
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _joining = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return YsDialogFrame(
      maxWidth: 400,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Join Shared Session',
                style: TextStyle(
                  color: YsColors.foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: YsSpace.s4),
              FTextField(
                key: const Key('join-share-code'),
                control: FTextFieldControl.managed(controller: _controller),
                autofocus: true,
                maxLength: 30,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
                  _UpperCaseFormatter(),
                ],
                textAlign: TextAlign.center,
                hint: 'A3K9PX-XXXXXXXXXXXXXXXX',
                style: .delta(
                  contentTextStyle: .delta([
                    .base(
                      const .delta(
                        fontFamily: kYsMonoFontFamily,
                        fontFamilyFallback: kYsMonoFontFallback,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ]),
                ),
                error: _error == null ? null : Text(_error!),
                onSubmit: (_) => _join(context),
              ),
              const SizedBox(height: YsSpace.s4),
              FButton(
                key: const Key('join-share-submit'),
                onPress: _joining ? null : () => _join(context),
                prefix: _joining ? const FCircularProgress(size: .sm) : null,
                child: const Text('Join'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

part of 'host_detail_panel.dart';

/// Pinned footer: last test result (SSH), then Delete (existing hosts,
/// destructive), Test (SSH only) and Save (primary).
class _PanelFooter extends StatelessWidget {
  final _HostDetailPanelState form;
  const _PanelFooter({required this.form});

  @override
  Widget build(BuildContext context) {
    final result = form._testResult;
    final busy = form._saving;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        YsSpace.s4,
        YsSpace.s3,
        YsSpace.s4,
        YsSpace.s3,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!form._isGraphical && result != null) ...[
            _TestResult(result: result),
            const SizedBox(height: YsSpace.s3),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!form._isNew) ...[
                FButton(
                  key: const ValueKey('host-delete-button'),
                  variant: .ghost,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  style: .delta(
                    contentStyle: .delta(
                      textStyle: .delta([
                        .all(const .delta(color: YsColors.error)),
                      ]),
                      iconStyle: .delta([
                        .all(const .delta(color: YsColors.error)),
                      ]),
                    ),
                  ),
                  prefix: const Icon(FLucideIcons.trash2),
                  onPress: busy ? null : form._delete,
                  child: _buttonText('Delete'),
                ),
                const SizedBox(width: YsSpace.s2),
              ],
              // Test + Save stay right-aligned; they stack instead of
              // overflowing when the panel is too narrow for one row.
              Expanded(
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: YsSpace.s2,
                  overflowSpacing: YsSpace.s2,
                  children: [
                    if (!form._isGraphical)
                      FButton(
                        key: const ValueKey('host-test-button'),
                        variant: .outline,
                        size: .sm,
                        mainAxisSize: MainAxisSize.min,
                        prefix: form._testing
                            ? const FCircularProgress(size: .sm)
                            : const Icon(FLucideIcons.zap),
                        onPress: (form._testing || busy) ? null : form._test,
                        child: _buttonText(form._testing ? 'Testing…' : 'Test'),
                      ),
                    FButton(
                      key: const ValueKey('host-save-button'),
                      size: .sm,
                      mainAxisSize: MainAxisSize.min,
                      prefix: busy ? const FCircularProgress(size: .sm) : null,
                      onPress: busy ? null : form._save,
                      child: _buttonText(form._isNew ? 'Save' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Connected · N ms" or the error, in status colours.
class _TestResult extends StatelessWidget {
  final ({bool success, int latencyMs, String? error}) result;
  const _TestResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.success ? YsColors.ok : YsColors.error;
    final text = Text(
      result.success
          ? 'Connected · ${result.latencyMs}ms'
          : result.error ?? 'Failed',
      // A long error must not push the footer off the panel.
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 12),
    );
    return Container(
      key: const ValueKey('host-test-result'),
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s3,
        vertical: YsSpace.s2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(YsRadius.control),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              result.success
                  ? FLucideIcons.circleCheck
                  : FLucideIcons.circleAlert,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: result.success
                ? text
                : Tooltip(
                    // The full error, when three lines cut it short.
                    message: text.data!,
                    child: text,
                  ),
          ),
        ],
      ),
    );
  }
}

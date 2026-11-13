import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'models.dart';

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Status / time / size summary, copy action and the Body / Headers tabs.
class HttpResponsePanel extends StatelessWidget {
  final HttpResponse? response;
  final bool loading;
  const HttpResponsePanel({
    super.key,
    required this.response,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: FCircularProgress());
    final r = response;
    if (r == null) return const WtHint('Send a request to see the response');

    final color = statusColor(r.statusCode, isError: r.isError);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: YsColors.sidebar,
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.s4,
            vertical: YsSpace.s2,
          ),
          child: Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: YsSpace.s2,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    r.statusCode == 0
                        ? 'Error'
                        : '${r.statusCode} ${r.reasonPhrase}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: YsSpace.s3),
              WtCaption('${r.durationMs} ms'),
              const SizedBox(width: YsSpace.s2),
              WtCaption(formatSize(r.sizeBytes)),
              const Spacer(),
              WtIconButton(
                buttonKey: const ValueKey('http-copy-body'),
                icon: FLucideIcons.copy,
                tooltip: 'Copy body',
                onPress: () => Clipboard.setData(ClipboardData(text: r.body)),
              ),
            ],
          ),
        ),
        Expanded(
          child: FTabs(
            expands: true,
            children: [
              FTabEntry(
                label: const Text('Body'),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(YsSpace.s3),
                  child: WtSelectableText(r.body),
                ),
              ),
              FTabEntry(
                label: const Text('Headers'),
                child: _Headers(headers: r.headers),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Headers extends StatelessWidget {
  final Map<String, String> headers;
  const _Headers({required this.headers});

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) return const WtHint('No headers');
    return ListView(
      padding: const EdgeInsets.all(YsSpace.s3),
      children: [
        for (final e in headers.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: Text(
                    e.key,
                    style: kWtMono.copyWith(color: YsColors.mutedForeground),
                  ),
                ),
                Expanded(child: WtSelectableText(e.value)),
              ],
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/mail_catcher_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'container_widgets.dart';

class MailCatcherScreen extends StatefulWidget {
  const MailCatcherScreen({super.key});

  @override
  State<MailCatcherScreen> createState() => _MailCatcherScreenState();
}

class _MailCatcherScreenState extends State<MailCatcherScreen> {
  late MailCatcherService _service;
  bool _running = false;
  List<CaughtEmail> _emails = [];
  CaughtEmail? _selected;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _service = MailCatcherService(context.read<SshService>());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    final ok = await _service.start(session.host);
    if (ok) {
      setState(() => _running = true);
      _pollTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } else {
      if (!mounted) return;
      AppSnack.error(
          context,
          _service.lastError ??
              'Failed to start SMTP server. Ensure python3 is installed.');
    }
  }

  Future<void> _stop() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    _pollTimer?.cancel();
    await _service.stop(session.host);
    setState(() => _running = false);
  }

  Future<void> _poll() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;
    final emails = await _service.fetchEmails(session.host);
    if (mounted) setState(() => _emails = emails);
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasSession =
        context.watch<SessionProvider>().activeSshSession != null;
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: YsSpace.s3,
                  vertical: YsSpace.s1,
                ),
                color: YsColors.sidebar,
                child: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Mail Catcher',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: YsColors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_emails.isNotEmpty) ...[
                      const SizedBox(width: YsSpace.s2),
                      YsTag('${_emails.length}'),
                    ],
                    const Spacer(),
                    if (_emails.isNotEmpty)
                      ContainerIconAction(
                        icon: FLucideIcons.listX,
                        tooltip: 'Clear all',
                        onPress: () => setState(() {
                          _emails = [];
                          _selected = null;
                        }),
                      ),
                    _running
                        ? ContainerIconAction(
                            icon: FLucideIcons.square,
                            tooltip: 'Stop',
                            onPress: _stop,
                          )
                        : ContainerIconAction(
                            icon: FLucideIcons.play,
                            tooltip: 'Start on port 1025',
                            active: true,
                            onPress: hasSession ? _start : null,
                          ),
                  ],
                ),
              ),
              if (_running)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: YsSpace.s3,
                    vertical: YsSpace.s1,
                  ),
                  color: YsColors.ok.withValues(alpha: 0.1),
                  child: const Row(
                    children: [
                      Icon(FLucideIcons.circle, size: 8, color: YsColors.ok),
                      SizedBox(width: 6),
                      Text(
                        'Listening on :1025',
                        style: TextStyle(color: YsColors.ok, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ColoredBox(
                  color: YsColors.sidebar,
                  child: _emails.isEmpty
                      ? const Center(
                          child: Text(
                            'No emails captured',
                            style: TextStyle(color: YsColors.mutedForeground),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _emails.length,
                          itemBuilder: (_, i) => _EmailRow(
                            subject: _emails[i].subject.isEmpty
                                ? '(no subject)'
                                : _emails[i].subject,
                            subtitle:
                                '${_emails[i].from} · ${_fmtTime(_emails[i].receivedAt)}',
                            selected: _selected == _emails[i],
                            onTap: () => setState(() => _selected = _emails[i]),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: YsColors.border),
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text(
                    'Select an email',
                    style: TextStyle(color: YsColors.mutedForeground),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(YsSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subject: ${_selected!.subject}',
                        style: const TextStyle(
                          color: YsColors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: YsSpace.s1),
                      Text('From: ${_selected!.from}', style: _meta),
                      Text('To: ${_selected!.to}', style: _meta),
                      Text(
                        'Received: ${_fmtTime(_selected!.receivedAt)}',
                        style: _meta,
                      ),
                      const SizedBox(height: YsSpace.s2),
                      const FDivider(
                        style: .delta(padding: .value(EdgeInsets.zero)),
                      ),
                      const SizedBox(height: YsSpace.s2),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _selected!.body,
                            style: const TextStyle(
                              color: YsColors.foreground,
                              fontFamily: kYsMonoFontFamily,
                              fontFamilyFallback: kYsMonoFontFallback,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  static const _meta = TextStyle(color: YsColors.mutedForeground, fontSize: 12);
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.subject,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String subject;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FTappable(
    semanticsLabel: subject,
    selected: selected,
    onPress: onTap,
    builder: (context, variants, child) {
      final hovered = variants.contains(FTappableVariant.hovered);
      final focused = variants.contains(FTappableVariant.focused);
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s3,
          vertical: YsSpace.s2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? YsColors.primary.withValues(alpha: 0.12)
              : hovered || focused
              ? YsColors.secondary
              : null,
          border: Border(
            left: BorderSide(
              color: selected || focused
                  ? YsColors.primary
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: child,
      );
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: YsColors.foreground, fontSize: 13),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: YsColors.mutedForeground, fontSize: 11),
        ),
      ],
    ),
  );
}

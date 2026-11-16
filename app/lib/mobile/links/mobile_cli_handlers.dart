import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../services/cli/cli_handlers.dart';
import '../../services/cli/host_resolver.dart';

/// [CliHandlers] for `yourssh://` links on mobile: saved hosts only.
class MobileCliHandlers implements CliHandlers {
  MobileCliHandlers({
    required this.hostProvider,
    required this.open,
    required this.appVersion,
  });

  final HostProvider hostProvider;

  /// Opens a session for [Host]; the source is recorded on the audit row.
  final Future<void> Function(Host host, String source) open;

  @override
  final String appVersion;

  @override
  List<Host> get hosts => hostProvider.allHosts;

  @override
  Future<void> connect(Host host, {required String source}) =>
      open(host, source);

  /// URLs never allow ad-hoc targets (the resolver is called with
  /// `allowAdHoc: false`); reaching this is a bug.
  @override
  Future<void> connectAdHoc(AdHocTarget target) =>
      throw StateError('ad-hoc connects are not available from links');

  @override
  Future<void> focusWindow() async {}
}

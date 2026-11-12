import '../../models/host.dart';
import 'host_resolver.dart';

/// What the app does for CLI / URL requests. Implemented in the app layer;
/// faked in tests.
abstract class CliHandlers {
  List<Host> get hosts;

  /// Opens a session to a saved host. [source] is `cli` or `url` and is
  /// recorded on the real connect audit row.
  Future<void> connect(Host host, {required String source});

  Future<void> connectAdHoc(AdHocTarget target);

  /// Raises and focuses the main window.
  Future<void> focusWindow();

  String get appVersion;
}

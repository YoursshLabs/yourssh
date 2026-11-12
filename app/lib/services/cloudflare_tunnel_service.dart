import '../models/host.dart';
import 'ssh_service.dart';
import 'web_tools_service.dart';

class TunnelStartResult {
  /// URL on success, null on failure.
  final String? url;

  /// Human-readable reason on failure (null when [url] is non-null).
  final String? error;

  const TunnelStartResult.success(String this.url) : error = null;
  const TunnelStartResult.failure(String this.error) : url = null;

  bool get ok => url != null;
}

class CloudflareTunnelService {
  final SshService _sshService;

  /// Remote state dir (mktemp -d, holds `log` and `pid`) per host+port. Static
  /// because the screen builds a fresh service for every start/stop call.
  static final Map<String, String> _stateDirs = {};
  static final _dirPattern = RegExp(r'^/[A-Za-z0-9_./-]+$');

  static String _key(Host host, int port) => '${host.id}:$port';

  CloudflareTunnelService(this._sshService);

  /// Starts cloudflared quick tunnel on the remote server. Returns a structured
  /// result so callers can distinguish "not installed" / "exec failed" / "no URL
  /// in log" instead of silently rendering a generic error.
  Future<TunnelStartResult> startQuickTunnel(Host host, int port) async {
    try {
      final cmd = '''
        d=\$(mktemp -d) || exit 1
        nohup cloudflared tunnel --url http://localhost:$port > "\$d/log" 2>&1 &
        echo \$! > "\$d/pid"
        echo "DIR:\$d"
        sleep 3
        grep -o 'https://[^[:space:]]*trycloudflare.com' "\$d/log" | head -1
      ''';
      final result = await _sshService.exec(host, cmd, auditSource: 'devops');
      String? dir;
      String url = '';
      for (final line in result.stdout.split('\n')) {
        final l = line.trim();
        if (l.startsWith('DIR:')) {
          final d = l.substring(4);
          if (_dirPattern.hasMatch(d)) dir = d;
        } else if (l.startsWith('https://')) {
          url = l;
        }
      }
      if (dir != null) _stateDirs[_key(host, port)] = dir;
      if (url.isNotEmpty) return TunnelStartResult.success(url);
      // No URL emitted yet — either cloudflared crashed or took longer than 3s.
      // The log path is the actionable hint.
      return TunnelStartResult.failure(
        'No trycloudflare URL in ${dir ?? 'the tunnel'} log within 3s. '
        'Inspect ${dir == null ? 'the log' : '$dir/log'} on the server for details.',
      );
    } catch (e) {
      return TunnelStartResult.failure('SSH exec failed: $e');
    }
  }

  Future<void> stopTunnel(Host host, int port) async {
    final dir = _stateDirs.remove(_key(host, port));
    final String cmd;
    if (dir != null) {
      final pidFile = WebToolsService.shellQuote('$dir/pid');
      cmd = 'kill \$(cat $pidFile) 2>/dev/null; '
          'rm -rf ${WebToolsService.shellQuote(dir)}';
    } else {
      // State unknown (e.g. app restarted): anchored pattern, with a bracket
      // so it cannot match the `sh -c` that runs this pkill.
      cmd = "pkill -f '^[c]loudflared tunnel --url http://localhost:$port\$' "
          '2>/dev/null; true';
    }
    await _sshService.exec(host, cmd, auditSource: 'devops');
  }

  Future<bool> isCloudflaredInstalled(Host host) async {
    final result = await _sshService.exec(host, 'which cloudflared 2>/dev/null', auditSource: 'devops');
    return result.stdout.trim().isNotEmpty;
  }
}

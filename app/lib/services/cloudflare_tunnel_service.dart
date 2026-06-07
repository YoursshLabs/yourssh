import '../models/host.dart';
import 'ssh_service.dart';

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

  CloudflareTunnelService(this._sshService);

  /// Starts cloudflared quick tunnel on the remote server. Returns a structured
  /// result so callers can distinguish "not installed" / "exec failed" / "no URL
  /// in log" instead of silently rendering a generic error.
  Future<TunnelStartResult> startQuickTunnel(Host host, int port) async {
    try {
      final cmd = '''
        nohup cloudflared tunnel --url http://localhost:$port > /tmp/cf_tunnel_$port.log 2>&1 &
        sleep 3
        grep -o 'https://[^[:space:]]*trycloudflare.com' /tmp/cf_tunnel_$port.log | head -1
      ''';
      final result = await _sshService.exec(host, cmd, auditSource: 'devops');
      final url = result.stdout.trim();
      if (url.startsWith('https://')) return TunnelStartResult.success(url);
      // No URL emitted yet — either cloudflared crashed or took longer than 3s.
      // The log path is the actionable hint.
      return TunnelStartResult.failure(
        'No trycloudflare URL in /tmp/cf_tunnel_$port.log within 3s. '
        'Inspect the log on the server for details.',
      );
    } catch (e) {
      return TunnelStartResult.failure('SSH exec failed: $e');
    }
  }

  Future<void> stopTunnel(Host host, int port) async {
    await _sshService.exec(
      host,
      "pkill -f 'cloudflared.*$port' 2>/dev/null; rm -f /tmp/cf_tunnel_$port.log",
      auditSource: 'devops',
    );
  }

  Future<bool> isCloudflaredInstalled(Host host) async {
    final result = await _sshService.exec(host, 'which cloudflared 2>/dev/null', auditSource: 'devops');
    return result.stdout.trim().isNotEmpty;
  }
}

import '../models/host.dart';
import 'ssh_service.dart';

class CloudflareTunnelService {
  final SshService _sshService;

  CloudflareTunnelService(this._sshService);

  /// Starts cloudflared quick tunnel on the remote server.
  /// Returns the public trycloudflare.com URL if successful, or null on failure.
  Future<String?> startQuickTunnel(Host host, int port) async {
    try {
      final cmd = '''
        nohup cloudflared tunnel --url http://localhost:$port > /tmp/cf_tunnel_$port.log 2>&1 &
        sleep 3
        grep -o 'https://[^[:space:]]*trycloudflare.com' /tmp/cf_tunnel_$port.log | head -1
      ''';
      final result = await _sshService.exec(host, cmd);
      final url = result.stdout.trim();
      if (url.startsWith('https://')) return url;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> stopTunnel(Host host, int port) async {
    await _sshService.exec(
      host,
      "pkill -f 'cloudflared.*$port' 2>/dev/null; rm -f /tmp/cf_tunnel_$port.log",
    );
  }

  Future<bool> isCloudflaredInstalled(Host host) async {
    final result = await _sshService.exec(host, 'which cloudflared 2>/dev/null');
    return result.stdout.trim().isNotEmpty;
  }
}

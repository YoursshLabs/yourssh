import 'host.dart';

/// What an SFTP panel slot points at: the local filesystem or a saved host.
sealed class PanelSource {
  const PanelSource();
}

class LocalSource extends PanelSource {
  const LocalSource();

  @override
  bool operator ==(Object other) => other is LocalSource;

  @override
  int get hashCode => 0x10ca1;
}

class HostSource extends PanelSource {
  final Host host;
  const HostSource(this.host);

  @override
  bool operator ==(Object other) => other is HostSource && other.host.id == host.id;

  @override
  int get hashCode => host.id.hashCode;
}

/// How a transfer between two panel sources is carried out.
enum TransferKind { localCopy, upload, download, remoteRelay }

/// Pure dispatch for the two-panel transfer matrix. Same-host remote→remote
/// still relays through a local temp file (no server-side copy).
TransferKind transferKindFor(PanelSource src, PanelSource dst) {
  return switch ((src, dst)) {
    (LocalSource(), LocalSource()) => TransferKind.localCopy,
    (LocalSource(), HostSource()) => TransferKind.upload,
    (HostSource(), LocalSource()) => TransferKind.download,
    (HostSource(), HostSource()) => TransferKind.remoteRelay,
  };
}

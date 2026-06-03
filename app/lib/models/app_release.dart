/// Status of the in-app update check / download flow.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

/// A downloadable artifact attached to a GitHub release.
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  // "sha256:<hex>" from GitHub API digest field; null when not provided.
  final String? digest;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.digest,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: (json['name'] as String?) ?? '',
        downloadUrl: (json['browser_download_url'] as String?) ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        digest: json['digest'] as String?,
      );
}

/// A GitHub release as returned by the `releases/latest` endpoint.
class AppRelease {
  /// Tag with the leading `v` stripped, e.g. `0.2.0`.
  final String version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const AppRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    this.publishedAt,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final published = json['published_at'] as String?;
    return AppRelease(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      tagName: tag,
      name: (json['name'] as String?) ?? tag,
      notes: (json['body'] as String?) ?? '',
      htmlUrl: (json['html_url'] as String?) ?? '',
      publishedAt: published == null ? null : DateTime.parse(published),
      assets: ((json['assets'] as List?) ?? const [])
          .map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

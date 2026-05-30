class S3BucketEntry {
  final String key;
  final bool isPrefix;
  final int size;
  final DateTime? lastModified;
  final String? etag;

  const S3BucketEntry({
    required this.key,
    required this.isPrefix,
    this.size = 0,
    this.lastModified,
    this.etag,
  });

  String get name {
    final parts = key.split('/');
    if (isPrefix) {
      return parts.length >= 2 ? parts[parts.length - 2] : parts.last;
    }
    return parts.last;
  }

  String get displaySize {
    if (isPrefix) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

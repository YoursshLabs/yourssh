class SftpEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  /// Raw st_mode from the server (file-type + permission bits), null when
  /// the server did not report it. Used by the Edit Permissions dialog.
  final int? mode;

  const SftpEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    this.mode,
  });

  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get formattedSize {
    if (isDirectory) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get sortKey => (isDirectory ? '0' : '1') + name.toLowerCase();

  String get kindLabel {
    if (isDirectory) return 'folder';
    if (extension.isEmpty) return 'document';
    return extension;
  }
}

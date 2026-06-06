// app/lib/util/bulk_format.dart
// Shared formatting for the bulk action widgets. No Flutter imports.

/// 1-decimal B/KB/MB byte formatter used by the bulk progress rows/chips.
String formatByteSize(int b) {
  if (b >= 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '$b B';
}

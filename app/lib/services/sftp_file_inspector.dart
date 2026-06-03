// app/lib/services/sftp_file_inspector.dart
//
// Pure helpers that decide whether an SFTP entry can be edited in-app.
// No Flutter or dart:io imports so the logic stays trivially unit-testable.
import '../models/sftp_entry.dart';

/// Files larger than this are not loaded into the in-app editor.
const int kMaxEditableFileSize = 5 * 1024 * 1024; // 5 MB

/// Extensions always treated as binary (pointless to edit as text).
const Set<String> kBinaryExtensions = {
  // images
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'ico', 'webp', 'tiff', 'heic',
  // audio / video
  'mp3', 'wav', 'ogg', 'flac', 'aac', 'mp4', 'mkv', 'avi', 'mov', 'webm',
  // archives
  'zip', 'tar', 'gz', 'bz2', 'xz', 'zst', '7z', 'rar', 'jar', 'war',
  // executables / libraries / object code
  'exe', 'dll', 'so', 'dylib', 'bin', 'o', 'a', 'class', 'wasm',
  // documents
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt',
  // misc binary formats
  'sqlite', 'db', 'iso', 'img', 'dmg', 'ttf', 'otf', 'woff', 'woff2',
};

enum EditBlockReason { none, binaryExtension, tooLarge }

/// Pre-download check: can [entry] be opened in the in-app editor?
/// Uses only metadata from the directory listing (name + size).
EditBlockReason editBlockReason(SftpEntry entry) {
  if (kBinaryExtensions.contains(entry.extension)) {
    return EditBlockReason.binaryExtension;
  }
  if (entry.size > kMaxEditableFileSize) return EditBlockReason.tooLarge;
  return EditBlockReason.none;
}

/// Post-download check: a null byte within the first 8 KB marks the content
/// as binary even when the extension looked editable.
bool looksBinary(List<int> bytes) {
  final limit = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

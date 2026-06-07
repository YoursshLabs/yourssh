import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Locates the yourssh_rdp dynamic library. Search order: bundled release
/// locations (relative to the running executable), plain name (rpath /
/// system lookup), then repo-relative dev paths.
ExternalLibrary loadYoursshRdpLibrary() {
  Object? lastError;
  for (final path in _candidates()) {
    try {
      return ExternalLibrary.open(path);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError('yourssh_rdp native library not found: $lastError');
}

List<String> _candidates() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isMacOS) {
    return [
      '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libyourssh_rdp.dylib',
      'libyourssh_rdp.dylib',
      // Dev: running flutter test from within packages/yourssh_rdp/
      '${Directory.current.path}/assets/native/macos/libyourssh_rdp.dylib',
      // Dev: running flutter run/test from app/ or repo root
      '${Directory.current.path}/packages/yourssh_rdp/assets/native/macos/libyourssh_rdp.dylib',
      '${Directory.current.path}/../packages/yourssh_rdp/assets/native/macos/libyourssh_rdp.dylib',
    ];
  }
  if (Platform.isLinux) {
    return [
      '$exeDir/lib/libyourssh_rdp.so',
      'libyourssh_rdp.so',
      '${Directory.current.path}/assets/native/linux/libyourssh_rdp.so',
      '${Directory.current.path}/packages/yourssh_rdp/assets/native/linux/libyourssh_rdp.so',
      '${Directory.current.path}/../packages/yourssh_rdp/assets/native/linux/libyourssh_rdp.so',
    ];
  }
  return [
    '$exeDir\\yourssh_rdp.dll',
    'yourssh_rdp.dll',
    '${Directory.current.path}\\assets\\native\\windows\\yourssh_rdp.dll',
    '${Directory.current.path}\\packages\\yourssh_rdp\\assets\\native\\windows\\yourssh_rdp.dll',
    '${Directory.current.path}\\..\\packages\\yourssh_rdp\\assets\\native\\windows\\yourssh_rdp.dll',
  ];
}

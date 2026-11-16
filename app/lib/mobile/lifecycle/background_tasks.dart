import 'package:flutter/services.dart';

/// An OS grant to keep running briefly after the app leaves the foreground.
class BackgroundLease {
  const BackgroundLease({required this.id, this.remaining});

  final int id;

  /// Time the OS says is left; null when unknown.
  final Duration? remaining;
}

/// Asks the OS for background execution time (iOS
/// `beginBackgroundTask(withName:expirationHandler:)`).
abstract class BackgroundTasks {
  /// Null when the OS refuses.
  Future<BackgroundLease?> begin();
  Future<void> end(int id);
}

class MethodChannelBackgroundTasks implements BackgroundTasks {
  MethodChannelBackgroundTasks(
      [MethodChannel channel = const MethodChannel('yourssh/background')])
      : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<BackgroundLease?> begin() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('begin');
      if (r == null) return null;
      final id = r['id'] as int?;
      if (id == null) return null;
      final ms = r['remainingMs'] as int?;
      return BackgroundLease(
          id: id,
          remaining: (ms == null || ms < 0) ? null : Duration(milliseconds: ms));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> end(int id) async {
    try {
      await _channel.invokeMethod<void>('end', id);
    } on PlatformException {
      // The task is already over (the OS expired it).
    } on MissingPluginException {
      // No native side (tests, other platforms).
    }
  }
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../models/share_event.dart';

class ShareSessionService {
  static const maxBufferLength = 500 * 1024;
  static const _chunkSize = 80 * 1024;
  static const _pluginId = 'yourssh_share_service';
  static const _broadcastEvent = 'share';

  final _outputBuffer = StringBuffer();
  int _bufferLength = 0;

  HookBus? _hookBus;
  String? _sessionId;

  /// The SSH session ID currently being shared, or null when not sharing.
  String? get activeSessionId => _sessionId;

  SupabaseClient? _client;
  RealtimeChannel? _channel;

  Terminal? _guestTerminal;
  final _chunkAccumulator = <int, String>{};
  int _expectedChunks = 0;

  final _events = StreamController<ShareEvent>.broadcast();
  Stream<ShareEvent> get events => _events.stream;

  /// Callback fired when a guest leaves (presence leave). Provides [guestId].
  void Function(String guestId)? onPresenceLeave;

  // ─── Constructor ─────────────────────────────────────

  ShareSessionService();

  /// Named constructor for unit tests — no external dependencies required.
  ShareSessionService.forTest();

  // ─── Helpers ─────────────────────────────────────────

  static String generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _appendToBuffer(String text) {
    _outputBuffer.write(text);
    _bufferLength += text.length;
    if (_bufferLength > maxBufferLength) {
      final s = _outputBuffer.toString();
      final trimmed = s.substring(s.length - maxBufferLength ~/ 2);
      _outputBuffer.clear();
      _outputBuffer.write(trimmed);
      _bufferLength = trimmed.length;
    }
  }

  // ─── Host API ─────────────────────────────────────────

  Future<String> startSharing(
    String sessionId,
    HookBus hookBus,
    String supabaseUrl,
    String anonKey,
  ) async {
    _sessionId = sessionId;
    _hookBus = hookBus;
    _outputBuffer.clear();
    _bufferLength = 0;

    hookBus.register('terminal.output', _pluginId, (event) {
      if (event.sessionId == sessionId) {
        _appendToBuffer(event.data);
        _broadcastOutput(event.data);
      }
      return event.data;
    });

    final code = generateShareCode();
    _client = SupabaseClient(supabaseUrl, anonKey);
    _channel = _client!.channel('share:$code');

    _channel!
        .onBroadcast(
          event: _broadcastEvent,
          callback: (payload) => _onHostReceived(payload),
        )
        .onPresenceLeave((leavePayload) {
          for (final p in leavePayload.leftPresences) {
            final guestId = p.payload['guestId'] as String?;
            if (guestId != null) {
              onPresenceLeave?.call(guestId);
            }
          }
        })
        .subscribe();

    return code;
  }

  void _onHostReceived(Map<String, dynamic> payload) {
    try {
      final event = ShareEvent.fromJson(payload);
      _events.add(event);
    } catch (e) {
      debugPrint('[ShareSessionService] host received unknown event: $e');
    }
  }

  void _broadcastOutput(String text) {
    _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.output(text).toJson(),
    );
  }

  Future<void> sendSnapshot(String guestId) async {
    if (_channel == null) return;
    final snapshot = _outputBuffer.toString();
    if (snapshot.length <= _chunkSize) {
      final payload = ShareEvent.snapshot(snapshot).toJson()
        ..['targetGuestId'] = guestId;
      await _channel!.sendBroadcastMessage(
        event: _broadcastEvent,
        payload: payload,
      );
    } else {
      final chunks = <String>[];
      for (var i = 0; i < snapshot.length; i += _chunkSize) {
        chunks.add(snapshot.substring(i, (i + _chunkSize).clamp(0, snapshot.length)));
      }
      for (var i = 0; i < chunks.length; i++) {
        final payload = ShareEvent.snapshotChunk(chunks[i], i, chunks.length).toJson()
          ..['targetGuestId'] = guestId;
        await _channel!.sendBroadcastMessage(
          event: _broadcastEvent,
          payload: payload,
        );
      }
    }
  }

  Future<void> sendRejected(String guestId, String reason) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.rejected(reason).toJson(),
    );
  }

  Future<void> grantControl(String guestId) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.controlGrant(guestId).toJson(),
    );
  }

  Future<void> revokeControl() async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.controlRevoke().toJson(),
    );
  }

  Future<void> stopSharing() async {
    _hookBus?.unregisterAll(_pluginId);
    _hookBus = null;
    _sessionId = null;
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.ended().toJson(),
    );
    if (_client != null && _channel != null) {
      await _client!.removeChannel(_channel!);
    }
    _channel = null;
    _client?.dispose();
    _client = null;
    _outputBuffer.clear();
    _bufferLength = 0;
  }

  // ─── Guest API ────────────────────────────────────────

  final _guestId = const Uuid().v4();
  String get guestId => _guestId;

  Future<void> joinSession(
    String shareCode,
    String supabaseUrl,
    String anonKey,
    Terminal localTerminal,
  ) async {
    _guestTerminal = localTerminal;
    _client = SupabaseClient(supabaseUrl, anonKey);
    _channel = _client!.channel('share:$shareCode');

    _channel!
        .onBroadcast(
          event: _broadcastEvent,
          callback: (payload) => _onGuestReceived(payload),
        )
        .subscribe((status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({'guestId': _guestId, 'role': 'guest'});
            await _channel!.sendBroadcastMessage(
              event: _broadcastEvent,
              payload: ShareEvent.joinRequest(_guestId).toJson(),
            );
          }
        });
  }

  void _onGuestReceived(Map<String, dynamic> payload) {
    ShareEvent event;
    try {
      event = ShareEvent.fromJson(payload);
    } catch (e) {
      debugPrint('[ShareSessionService] guest received unknown event: $e');
      return;
    }

    // For snapshot events, only process if targeted at this guest
    final targetGuestId = payload['targetGuestId'] as String?;
    final isSnapshotEvent = event.type == ShareEventType.snapshot ||
        event.type == ShareEventType.snapshotChunk;
    if (isSnapshotEvent && targetGuestId != null && targetGuestId != _guestId) {
      return; // Not for us
    }

    switch (event.type) {
      case ShareEventType.output:
        if (event.data != null) _guestTerminal?.write(event.data!);
      case ShareEventType.snapshot:
        _chunkAccumulator.clear();
        _expectedChunks = 0;
        if (event.data != null) _guestTerminal?.write(event.data!);
        _events.add(event);
      case ShareEventType.snapshotChunk:
        final index = event.chunkIndex ?? 0;
        final total = event.chunkTotal ?? 1;
        if (total <= 0 || index >= total) break;
        _expectedChunks = total;
        _chunkAccumulator[index] = event.data ?? '';
        if (_chunkAccumulator.length == _expectedChunks) {
          // Verify all expected indices are present before reassembly
          final allPresent = List.generate(_expectedChunks, (i) => _chunkAccumulator.containsKey(i)).every((v) => v);
          if (!allPresent) break;
          final full = List.generate(_expectedChunks, (i) => _chunkAccumulator[i]!).join();
          _guestTerminal?.write(full);
          _chunkAccumulator.clear();
          _events.add(ShareEvent.snapshot(full));
        }
      case ShareEventType.controlGrant:
        _events.add(event);
      case ShareEventType.controlRevoke:
        _events.add(event);
      case ShareEventType.rejected:
        _events.add(event);
      case ShareEventType.ended:
        _events.add(event);
      case ShareEventType.input:
        break;
      case ShareEventType.joinRequest:
        break;
    }
  }

  Future<void> sendGuestInput(String data) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.input(data).toJson(),
    );
  }

  Future<void> leaveSession() async {
    await _channel?.untrack();
    if (_client != null && _channel != null) {
      await _client!.removeChannel(_channel!);
    }
    _channel = null;
    _client?.dispose();
    _client = null;
    _guestTerminal = null;
    _chunkAccumulator.clear();
  }

  // ─── Test helpers ────────────────────────────────────

  void appendToBufferForTest(String text) => _appendToBuffer(text);
  int get bufferLengthForTest => _bufferLength;
  String get bufferSnapshotForTest => _outputBuffer.toString();

  // ─── Dispose ─────────────────────────────────────────

  Future<void> dispose() async {
    if (_hookBus != null) await stopSharing();
    if (_guestTerminal != null) await leaveSession();
    await _events.close();
  }
}

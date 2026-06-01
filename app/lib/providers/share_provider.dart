import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../models/share_event.dart';
import '../models/ssh_session.dart';
import '../services/share_session_service.dart';
import 'session_provider.dart';
import 'sync_provider.dart';

class ShareProvider extends ChangeNotifier {
  final SyncProvider _syncProvider;
  SessionProvider? _sessionProvider;
  HookBus? _hookBus;

  ShareSessionService? _service;
  StreamSubscription<ShareEvent>? _eventSub;

  bool _isSharing = false;
  String? _shareCode;
  String? _sharingSessionId;
  final Set<String> _guests = {};
  String? _controlledBy;

  bool _isGuest = false;
  String? _viewingSessionId;
  bool _hasControl = false;
  bool _sessionEnded = false;

  bool get canShare => _syncProvider.isSupabaseConfigured;
  bool get isSharing => _isSharing;
  String? get shareCode => _shareCode;
  String? get sharingSessionId => _sharingSessionId;
  Set<String> get guests => Set.unmodifiable(_guests);
  String? get controlledBy => _controlledBy;
  bool get isGuest => _isGuest;
  String? get viewingSessionId => _viewingSessionId;
  bool get hasControl => _hasControl;
  bool get sessionEnded => _sessionEnded;

  void Function(String)? onGuestInput;

  ShareProvider({
    required SyncProvider syncProvider,
    SessionProvider? sessionProvider,
    HookBus? hookBus,
  })  : _syncProvider = syncProvider, // ignore: prefer_initializing_formals
        _sessionProvider = sessionProvider, // ignore: prefer_initializing_formals
        _hookBus = hookBus { // ignore: prefer_initializing_formals
    _syncProvider.addListener(_onSyncChanged);
  }

  void wireDependencies(SessionProvider sessionProvider, HookBus hookBus) {
    _sessionProvider = sessionProvider;
    _hookBus = hookBus;
    notifyListeners();
  }

  void _onSyncChanged() => notifyListeners();

  // ─── Host ────────────────────────────────────────────

  Future<String> startSharing(String sessionId) async {
    if (_isSharing) return _shareCode!;
    assert(canShare, 'canShare must be true before calling startSharing');
    assert(_hookBus != null, '_hookBus must be wired via wireDependencies() before calling startSharing');
    _sharingSessionId = sessionId;
    final service = ShareSessionService();
    service.onPresenceLeave = (guestId) {
      _guests.remove(guestId);
      if (_controlledBy == guestId) {
        _controlledBy = null;
      }
      notifyListeners();
    };
    _service = service;

    final code = await service.startSharing(
      sessionId,
      _hookBus!,
      _syncProvider.supabaseUrl,
      _syncProvider.supabaseAnonKey,
    );
    _isSharing = true;
    _shareCode = code;
    _guests.clear();
    _controlledBy = null;
    _eventSub = service.events.listen(_onHostEvent);
    notifyListeners();
    return code;
  }

  void _onHostEvent(ShareEvent event) {
    switch (event.type) {
      case ShareEventType.joinRequest:
        final guestId = event.guestId;
        if (guestId == null) return;
        if (_guests.length >= 5) {
          _service?.sendRejected(guestId, 'full');
        } else {
          _guests.add(guestId);
          _service?.sendSnapshot(guestId);
          notifyListeners();
        }
      case ShareEventType.input:
        onGuestInput?.call(event.data ?? '');
      default:
        break;
    }
  }

  Future<void> grantControl(String guestId) async {
    _controlledBy = guestId;
    await _service?.grantControl(guestId);
    notifyListeners();
  }

  Future<void> revokeControl() async {
    _controlledBy = null;
    await _service?.revokeControl();
    notifyListeners();
  }

  Future<void> stopSharing() async {
    _eventSub?.cancel();
    _eventSub = null;
    await _service?.stopSharing();
    _service = null;
    _isSharing = false;
    _shareCode = null;
    _sharingSessionId = null;
    _guests.clear();
    _controlledBy = null;
    notifyListeners();
  }

  // ─── Guest ───────────────────────────────────────────

  Future<void> joinSession(
    String shareCode,
    String supabaseUrl,
    String anonKey,
  ) async {
    // Clean up any existing guest session first
    if (_isGuest) await leaveSession();

    final watchSession = SshSession.watch(watchedTitle: shareCode);
    _viewingSessionId = watchSession.id;
    _isGuest = true;
    _hasControl = false;
    _sessionEnded = false;

    _sessionProvider?.addWatchSession(watchSession);

    final service = ShareSessionService();
    _service = service;
    _eventSub = service.events
        .listen((event) => _onGuestEvent(event, service.guestId));

    await service.joinSession(
      shareCode,
      supabaseUrl,
      anonKey,
      watchSession.terminal,
    );
    notifyListeners();
  }

  void _onGuestEvent(ShareEvent event, String myGuestId) {
    switch (event.type) {
      case ShareEventType.snapshot:
        notifyListeners();
      case ShareEventType.controlGrant:
        if (event.guestId == myGuestId) {
          _hasControl = true;
          notifyListeners();
        }
      case ShareEventType.controlRevoke:
        _hasControl = false;
        notifyListeners();
      case ShareEventType.rejected:
        _cleanupGuest();
        notifyListeners();
      case ShareEventType.ended:
        _sessionEnded = true;
        _hasControl = false;
        notifyListeners();
      default:
        break;
    }
  }

  Future<void> sendGuestInput(String data) async {
    if (_hasControl) await _service?.sendGuestInput(data);
  }

  Future<void> leaveSession() async {
    _eventSub?.cancel();
    _eventSub = null;
    await _service?.leaveSession();
    _service = null;
    if (_viewingSessionId != null) {
      _sessionProvider?.removeWatchSession(_viewingSessionId!);
    }
    _cleanupGuest();
    notifyListeners();
  }

  void _cleanupGuest() {
    _isGuest = false;
    _viewingSessionId = null;
    _hasControl = false;
    _sessionEnded = false;
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onSyncChanged);
    _eventSub?.cancel();
    super.dispose();
  }
}

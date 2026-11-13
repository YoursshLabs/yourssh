import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/lifecycle/background_tasks.dart';
import 'package:yourssh/mobile/lifecycle/mobile_lifecycle_coordinator.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/port_forward_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

late List<String> log;

class _Sessions extends SessionProvider {
  _Sessions() : super(SshService(StorageService()), TabMetadataService());
  List<String> get calls => log;

  @override
  void pauseAll() => log.add('sessions.pauseAll');

  @override
  Future<void> resumePaused(
      {Duration stagger = const Duration(milliseconds: 300)}) async {
    log.add('sessions.resumePaused');
  }

  @override
  Future<void> verifyLive(
      {Duration timeout = const Duration(seconds: 3)}) async {
    log.add('sessions.verifyLive');
  }
}

class _Forwards extends PortForwardService {
  _Forwards(this.running)
      : super(
          acquireTransport: (_) => throw UnimplementedError(),
          resolveHost: (_) => null,
          onStatus: (_, __, {error}) {},
          onConnections: (_, __) {},
        );
  Set<String> running;
  Completer<void>? stopGate;

  @override
  bool isRunning(String id) => running.contains(id);

  @override
  Future<void> stopAll() async {
    log.add('forwards.stopAll');
    await stopGate?.future;
    running = {};
  }

  @override
  Future<void> start(PortForward fwd) async => log.add('forwards.start:${fwd.id}');
}

class _Rules extends PortForwardProvider {
  _Rules(this.rules);
  final List<PortForward> rules;
  @override
  List<PortForward> get forwards => rules;
}

class _Tasks implements BackgroundTasks {
  _Tasks(this.remaining);
  final Duration? remaining;
  final ended = <int>[];
  int lastId = 0;
  bool refuse = false;
  final gates = <Completer<void>>[];
  bool gated = false;

  @override
  Future<BackgroundLease?> begin() async {
    if (refuse) return null;
    final id = ++lastId;
    if (gated) {
      final g = Completer<void>();
      gates.add(g);
      await g.future;
    }
    return BackgroundLease(id: id, remaining: remaining);
  }

  @override
  Future<void> end(int id) async {
    log.add('tasks.end');
    ended.add(id);
  }
}

PortForward _fwd(String id) =>
    PortForward(id: id, label: id, type: ForwardType.local, localPort: 1000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Sessions sessions;
  late _Forwards forwards;
  late _Tasks tasks;
  late MobileLifecycleCoordinator c;

  void build({Duration? remaining, Set<String> running = const {}}) {
    SharedPreferences.setMockInitialValues({});
    log = [];
    sessions = _Sessions();
    forwards = _Forwards(running);
    tasks = _Tasks(remaining);
    c = MobileLifecycleCoordinator(
      sessions: sessions,
      forwards: forwards,
      forwardRules: _Rules([_fwd('a'), _fwd('b'), _fwd('c')]),
      tasks: tasks,
      stagger: Duration.zero,
    );
  }

  test('a quick app switch pauses nothing and ends the task', () {
    fakeAsync((fa) {
      build();
      c.onBackground();
      fa.elapse(const Duration(seconds: 10));
      c.onForeground();
      fa.flushMicrotasks();
      expect(sessions.calls, isNot(contains('sessions.pauseAll')));
      expect(tasks.ended, [tasks.lastId]);
      expect(tasks.ended, hasLength(1));
      c.dispose();
    });
  });

  test('grace expiry stops forwards, then pauses sessions, then ends the task',
      () {
    fakeAsync((fa) {
      build();
      c.onBackground();
      fa.elapse(const Duration(seconds: 25));
      fa.flushMicrotasks();
      expect(log, ['forwards.stopAll', 'sessions.pauseAll', 'tasks.end']);
      c.dispose();
    });
  });

  test('grace follows the OS allowance', () {
    fakeAsync((fa) {
      build(remaining: const Duration(seconds: 12));
      c.onBackground();
      fa.elapse(const Duration(seconds: 6, milliseconds: 900));
      fa.flushMicrotasks();
      expect(log, isEmpty);
      fa.elapse(const Duration(milliseconds: 200));
      fa.flushMicrotasks();
      expect(log, contains('sessions.pauseAll'));
      c.dispose();
    });
  });

  test('no lease means no grace: pause immediately', () {
    fakeAsync((fa) {
      build();
      tasks.refuse = true;
      c.onBackground();
      fa.flushMicrotasks();
      expect(log, ['forwards.stopAll', 'sessions.pauseAll']);
      c.dispose();
    });
  });

  test('a lease shorter than 5 s clamps the grace at zero', () {
    fakeAsync((fa) {
      build(remaining: const Duration(seconds: 3));
      c.onBackground();
      fa.flushMicrotasks();
      expect(log, contains('sessions.pauseAll'));
      c.dispose();
    });
  });

  test(
      'foreground resumes paused sessions, probes the rest, restarts recorded forwards',
      () {
    fakeAsync((fa) {
      build(running: {'a', 'b'});
      c.onBackground();
      fa.elapse(const Duration(seconds: 25));
      fa.flushMicrotasks();
      log.clear();
      c.onForeground();
      fa.flushMicrotasks();
      expect(log, [
        'sessions.resumePaused',
        'sessions.verifyLive',
        'forwards.start:a',
        'forwards.start:b',
      ]);
      // A second foreground without a pause restarts nothing.
      log.clear();
      c.onForeground();
      fa.flushMicrotasks();
      expect(log.where((e) => e.startsWith('forwards.start')), isEmpty);
      c.dispose();
    });
  });

  test('a foreground during a slow stopAll does not leave sessions paused', () {
    fakeAsync((fa) {
      build(running: {'a'});
      forwards.stopGate = Completer<void>();
      c.onBackground();
      fa.elapse(const Duration(seconds: 25));
      fa.flushMicrotasks();
      expect(log, ['forwards.stopAll']);
      c.onForeground();
      fa.flushMicrotasks();
      forwards.stopGate!.complete();
      fa.flushMicrotasks();
      expect(log, [
        'forwards.stopAll',
        'tasks.end',
        'sessions.resumePaused',
        'sessions.verifyLive',
        'forwards.start:a',
      ]);
      c.dispose();
    });
  });

  test('a foreground without a background (Face ID sheet) probes nothing', () {
    fakeAsync((fa) {
      build();
      c.onForeground();
      fa.flushMicrotasks();
      expect(log, isEmpty);
      c.dispose();
    });
  });

  test('background, foreground, background within one begin ends the first lease',
      () {
    fakeAsync((fa) {
      build();
      tasks.gated = true;
      c.onBackground();
      c.onForeground();
      c.onBackground();
      fa.flushMicrotasks();
      expect(tasks.gates, hasLength(2));
      tasks.gates[0].complete();
      tasks.gates[1].complete();
      fa.flushMicrotasks();
      expect(tasks.ended, [1]); // the stale lease is released at once
      fa.elapse(const Duration(seconds: 25));
      fa.flushMicrotasks();
      expect(log.where((e) => e == 'sessions.pauseAll'), hasLength(1));
      expect(tasks.ended, [1, 2]);
      c.dispose();
    });
  });

  test('dispose cancels a pending grace timer', () {
    fakeAsync((fa) {
      build();
      c.onBackground();
      fa.flushMicrotasks();
      c.dispose();
      fa.elapse(const Duration(seconds: 60));
      fa.flushMicrotasks();
      expect(log, isNot(contains('sessions.pauseAll')));
    });
  });

  group('MethodChannelBackgroundTasks', () {
    const channel = MethodChannel('yourssh/background');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('maps begin to a lease, -1 to unknown, and null to refused', () async {
      Object? reply = {'id': 7, 'remainingMs': 12000};
      messenger.setMockMethodCallHandler(channel, (_) async => reply);
      final t = MethodChannelBackgroundTasks();
      var l = await t.begin();
      expect(l!.id, 7);
      expect(l.remaining, const Duration(seconds: 12));
      reply = {'id': 8, 'remainingMs': -1};
      expect((await t.begin())!.remaining, isNull);
      reply = null;
      expect(await t.begin(), isNull);
    });

    test('end sends the id', () async {
      Object? got;
      messenger.setMockMethodCallHandler(channel, (c) async {
        got = [c.method, c.arguments];
        return null;
      });
      await MethodChannelBackgroundTasks().end(7);
      expect(got, ['end', 7]);
    });
  });
}

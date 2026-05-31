import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';

void main() {
  group('HookBus.fireTransform', () {
    test('returns original data when no handlers registered', () {
      final bus = HookBus();
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'hello'));
      expect(result, 'hello');
    });

    test('chains transform handlers in registration order', () {
      final bus = HookBus();
      bus.register('terminal.output', 'plugin-a',
          (e) => e.data.replaceAll('a', 'A'));
      bus.register('terminal.output', 'plugin-b',
          (e) => e.data.replaceAll('b', 'B'));
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'abc'));
      expect(result, 'ABc');
    });

    test('null return means pass-through', () {
      final bus = HookBus();
      bus.register('terminal.output', 'plugin-a', (e) => null);
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'hello'));
      expect(result, 'hello');
    });

    test('handler exception is swallowed, data passes through', () {
      final bus = HookBus();
      bus.register('terminal.output', 'bad-plugin',
          (e) => throw Exception('boom'));
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'safe'));
      expect(result, 'safe');
    });
  });

  group('HookBus.fireInterceptable', () {
    test('false cancels event and stops chain', () {
      final bus = HookBus();
      bool bCalled = false;
      bus.register('terminal.input', 'plugin-a', (e) => false);
      bus.register('terminal.input', 'plugin-b', (e) {
        bCalled = true;
        return e.data;
      });
      final result = bus.fireInterceptable('terminal.input',
          TransformEvent(sessionId: 's1', data: 'input'));
      expect(result, isNull);
      expect(bCalled, false);
    });

    test('returns transformed data when not cancelled', () {
      final bus = HookBus();
      bus.register('terminal.input', 'plugin-a', (e) => e.data.toUpperCase());
      final result = bus.fireInterceptable('terminal.input',
          TransformEvent(sessionId: 's1', data: 'hello'));
      expect(result, 'HELLO');
    });
  });

  group('HookBus.fireObserve', () {
    test('calls all observer handlers', () {
      final bus = HookBus();
      int count = 0;
      bus.registerObserver('session.connect', 'a', (_) { count++; });
      bus.registerObserver('session.connect', 'b', (_) { count++; });
      bus.fireObserve('session.connect',
          ObserveEvent(sessionId: 's1', payload: {}));
      expect(count, 2);
    });

    test('observer exception is swallowed', () {
      final bus = HookBus();
      bus.registerObserver('session.connect', 'bad', (_) => throw Exception('x'));
      expect(
        () => bus.fireObserve('session.connect',
            ObserveEvent(sessionId: 's1', payload: {})),
        returnsNormally,
      );
    });
  });

  test('unregisterAll removes all handlers for a plugin', () {
    final bus = HookBus();
    bus.register('terminal.output', 'plugin-x', (e) => 'X');
    bus.registerObserver('session.connect', 'plugin-x', (_) {});
    bus.unregisterAll('plugin-x');
    final result = bus.fireTransform('terminal.output',
        TransformEvent(sessionId: 's1', data: 'orig'));
    expect(result, 'orig');
  });
}

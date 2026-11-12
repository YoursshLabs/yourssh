import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/native/quickjs_runtime.dart';

void main() {
  test('evaluates simple JS without error', () {
    final rt = QuickJsRuntime();
    rt.eval('var x = 1 + 1;', filename: 'test.js');
    rt.dispose();
  });

  test('throws QuickJsException on syntax error', () {
    final rt = QuickJsRuntime();
    expect(
      () => rt.eval('invalid syntax !!!', filename: 'test.js'),
      throwsA(isA<QuickJsException>()),
    );
    rt.dispose();
  });

  test('calls registered host function', () {
    final rt = QuickJsRuntime();
    String? received;
    rt.registerHostFn('_host', 'echo', (arg) {
      received = arg;
      return '"ok"';
    });
    rt.eval('_host.echo(JSON.stringify({msg:"hello"}));', filename: 'test.js');
    expect(received, contains('hello'));
    rt.dispose();
  });

  test('callDispatch invokes plugin._dispatch and returns result', () {
    final rt = QuickJsRuntime();
    rt.eval('''
      var plugin = {
        _dispatch: function(event, ctxJson) {
          var ctx = JSON.parse(ctxJson);
          return JSON.stringify({data: ctx.data + "_transformed"});
        }
      };
    ''', filename: 'test.js');
    final result =
        rt.callDispatch('terminal.output', {'sessionId': 's1', 'data': 'hello'});
    expect(result, contains('hello_transformed'));
    rt.dispose();
  });

  test('infinite loop is interrupted by the eval timeout', () {
    final rt = QuickJsRuntime();
    final sw = Stopwatch()..start();
    expect(
      () => rt.eval('while(true){}',
          filename: 't.js', timeout: const Duration(milliseconds: 100)),
      throwsA(isA<QuickJsTimeoutException>()),
    );
    expect(sw.elapsedMilliseconds, lessThan(3000));
    // The runtime stays usable after a timeout.
    rt.eval('var ok = 1;', filename: 't.js');
    rt.dispose();
  });

  test('callDispatch times out on a runaway hook', () {
    final rt = QuickJsRuntime();
    rt.eval('var plugin = {_dispatch: function(){ while(true){} }};',
        filename: 't.js');
    expect(
      () => rt.callDispatch('terminal.output', {'sessionId': 's', 'data': 'x'},
          timeout: const Duration(milliseconds: 100)),
      throwsA(isA<QuickJsTimeoutException>()),
    );
    rt.dispose();
  });

  test('memory limit stops runaway allocation', () {
    final rt = QuickJsRuntime();
    expect(
      () => rt.eval(
          'var a=[]; while(true){ a.push(new Array(1000000).fill(1)); }',
          filename: 't.js',
          timeout: const Duration(seconds: 20)),
      throwsA(isA<QuickJsException>()),
    );
    rt.dispose();
  });

  test('deep recursion raises an error instead of crashing', () {
    final rt = QuickJsRuntime();
    expect(
      () => rt.eval('function f(){ return f()+1; } f();', filename: 't.js'),
      throwsA(isA<QuickJsException>()),
    );
    rt.dispose();
  });

  test('host callback results round-trip with large strings', () {
    final rt = QuickJsRuntime();
    rt.registerHostFn('_host', 'big', (_) => '"${'x' * 100000}"');
    rt.eval('var n = _host.big("null").length;', filename: 't.js');
    rt.dispose();
  });
}

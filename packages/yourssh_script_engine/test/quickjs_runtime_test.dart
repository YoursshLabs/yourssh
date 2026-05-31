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
}

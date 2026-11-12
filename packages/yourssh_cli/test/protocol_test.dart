import 'dart:convert';

import 'package:test/test.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

void main() {
  CliProtocolException? catchProto(void Function() f) {
    try {
      f();
    } on CliProtocolException catch (e) {
      return e;
    }
    return null;
  }

  group('CliRequest round trip', () {
    final cases = <String, Map<String, Object?>>{
      'connect': {'host': 'Prod DB'},
      'ls': {'tag': 'prod', 'filter': 'db'},
      'version': <String, Object?>{},
      'open': {'url': 'yourssh://connect/prod'},
      'activate': <String, Object?>{},
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final req = CliRequest(id: 'i1', token: 't', cmd: e.key, args: e.value);
        final line = req.encode();
        expect(line.contains('\n'), isFalse);
        final back = CliRequest.decode(line);
        expect(back.id, 'i1');
        expect(back.token, 't');
        expect(back.cmd, e.key);
        expect(back.args, e.value);
      });
    }
  });

  group('CliRequest.decode rejects', () {
    test('invalid JSON -> usage', () {
      expect(catchProto(() => CliRequest.decode('{'))?.code, CliExit.usage);
    });
    test('wrong v -> unreachable', () {
      final e = catchProto(() => CliRequest.decode(
          '{"v":2,"id":"a","token":"t","cmd":"ls","args":{}}'));
      expect(e?.code, CliExit.unreachable);
    });
    test('extra field -> usage', () {
      final e = catchProto(() => CliRequest.decode(
          '{"v":1,"id":"a","token":"t","cmd":"ls","args":{},"x":1}'));
      expect(e?.code, CliExit.usage);
    });
    test('missing field -> usage', () {
      final e = catchProto(
          () => CliRequest.decode('{"v":1,"id":"a","token":"t","cmd":"ls"}'));
      expect(e?.code, CliExit.usage);
    });
    test('oversize line -> usage', () {
      final line = jsonEncode({
        'v': 1,
        'id': 'a',
        'token': 't',
        'cmd': 'ls',
        'args': {'filter': 'x' * (70 * 1024)},
      });
      expect(catchProto(() => CliRequest.decode(line))?.code, CliExit.usage);
    });
  });

  group('CliResponse', () {
    test('success round trip', () {
      final r = CliResponse.decode(
          CliResponse.success('i', {'a': 1}).encode());
      expect(r.ok, isTrue);
      expect(r.id, 'i');
      expect(r.result, {'a': 1});
      expect(r.code, isNull);
    });
    test('failure round trip with candidates', () {
      final r = CliResponse.decode(CliResponse.failure('i', CliExit.usage, 'amb',
          candidates: [
            {'label': 'a'},
            {'label': 'b'}
          ]).encode());
      expect(r.ok, isFalse);
      expect(r.code, CliExit.usage);
      expect(r.error, 'amb');
      expect(r.candidates, hasLength(2));
    });
    test('response over 64 KiB decodes', () {
      final big = List.generate(2000, (i) => {'label': 'host-$i' * 10});
      final line = CliResponse.success('i', big).encode();
      expect(line.length, greaterThan(kMaxRequestBytes));
      expect((CliResponse.decode(line).result as List), hasLength(2000));
    });
    test('response over the response cap fails', () {
      final line =
          CliResponse.success('i', 'x' * (kMaxResponseBytes + 1)).encode();
      expect(catchProto(() => CliResponse.decode(line))?.code, CliExit.usage);
    });
    test('unknown field rejected', () {
      expect(
          catchProto(() =>
              CliResponse.decode('{"v":1,"id":"i","ok":true,"result":1,"x":1}'))
              ?.code,
          CliExit.usage);
    });
  });

  group('validateArgs', () {
    test('valid', () {
      validateArgs('connect', {'host': 'a'});
      validateArgs('ls', {});
      validateArgs('ls', {'tag': 't', 'filter': null});
      validateArgs('version', {});
      validateArgs('open', {'url': 'yourssh://x'});
      validateArgs('activate', {});
    });
    test('connect without host throws', () {
      expect(catchProto(() => validateArgs('connect', {}))?.code, CliExit.usage);
    });
    test('unknown command throws', () {
      expect(catchProto(() => validateArgs('rm', {}))?.code, CliExit.usage);
    });
    test('activate with args throws', () {
      expect(catchProto(() => validateArgs('activate', {'a': 1}))?.code,
          CliExit.usage);
    });
    test('version with args throws', () {
      expect(catchProto(() => validateArgs('version', {'a': 1}))?.code,
          CliExit.usage);
    });
    test('extra ls arg throws', () {
      expect(catchProto(() => validateArgs('ls', {'x': 'y'}))?.code,
          CliExit.usage);
    });
    test('non-string host throws', () {
      expect(catchProto(() => validateArgs('connect', {'host': 1}))?.code,
          CliExit.usage);
    });
  });

  test('kCliCommands has five commands', () {
    expect(kCliCommands,
        {'connect', 'ls', 'version', 'open', 'activate'});
  });

  test('exit codes', () {
    expect(CliExit.values.map((e) => e.code), [0, 1, 2, 3, 4]);
  });
}

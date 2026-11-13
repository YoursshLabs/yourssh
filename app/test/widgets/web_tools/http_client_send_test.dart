import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh_web_tools/src/screens/http_client.dart';

import '../../helpers/ys_test_app.dart';

class _Req {
  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final String body;
  _Req(this.method, this.uri, this.headers, this.body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides that fails every request with 400;
  // these tests talk to a real loopback server.
  setUp(() => HttpOverrides.global = null);

  late HttpServer server;
  late List<_Req> seen;
  int status = 200;
  String respBody = '{"a":1}';

  Future<void> startServer(WidgetTester tester) async {
    seen = [];
    status = 200;
    respBody = '{"a":1}';
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        final body = await utf8.decoder.bind(r).join();
        seen.add(_Req(r.method, r.uri, r.headers, body));
        r.response.statusCode = status;
        r.response.write(respBody);
        await r.response.close();
      });
    });
    addTearDown(() => server.close(force: true));
  }

  String base() => 'http://127.0.0.1:${server.port}';

  Future<void> pumpTool(WidgetTester tester) async {
    // Wide enough that all four request tabs are laid out.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ysTestApp(const HttpClientTool()));
    await tester.pumpAndSettle();
  }

  Finder inKey(String k) => find.descendant(
      of: find.byKey(ValueKey(k)), matching: find.byType(EditableText));

  Future<void> setUrl(WidgetTester tester, String url) async {
    await tester.enterText(inKey('http-url'), url);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.textContaining(label).first);
    await tester.pumpAndSettle();
  }

  Future<void> pickMethod(WidgetTester tester, String m) async {
    await tester.tap(find.byKey(const ValueKey('http-method-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(m));
    await tester.pumpAndSettle();
  }

  /// Presses [trigger] and lets the real socket IO finish, pumping the
  /// fake-async side in between, until [done] holds.
  Future<void> sendAndWait(WidgetTester tester, bool Function() done,
      {Future<void> Function()? trigger}) async {
    if (trigger != null) {
      await trigger();
    } else {
      await tester.tap(find.byKey(const ValueKey('http-send')));
    }
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(done(), isTrue, reason: 'request did not complete');
  }

  Future<void> sendOk(WidgetTester tester) => sendAndWait(
      tester, () => find.byType(HttpClientTool).evaluate().isNotEmpty &&
          (seen.isNotEmpty && find.byTooltip('Copy body').evaluate().isNotEmpty));

  testWidgets('GET: method, path, enabled params only, headers; response UI',
      (tester) async {
    await startServer(tester);
    await pumpTool(tester);
    await setUrl(tester, '${base()}/path?x=1&y=2');
    // Disable the y param: it must drop out of the URL and the request.
    await openTab(tester, 'Params');
    await tester.tap(find.byType(FCheckbox).at(1));
    await tester.pumpAndSettle();
    expect(inKey('http-url').evaluate().isNotEmpty, isTrue);
    await sendOk(tester);

    final r = seen.single;
    expect(r.method, 'GET');
    expect(r.uri.path, '/path');
    expect(r.uri.queryParameters, {'x': '1'});
    expect(r.headers.value('content-type'), startsWith('application/json'));

    // Response UI.
    final statusText = find.text('200 OK');
    expect(statusText, findsOneWidget);
    expect(tester.widget<Text>(statusText).style?.color, YsColors.ok);
    expect(find.textContaining(' ms'), findsOneWidget);
    expect(find.text('7 B'), findsOneWidget);
    expect(find.text('{\n  "a": 1\n}'), findsOneWidget);
    // History badge shows one entry.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('unticking a param keeps the URL caret in range',
      (tester) async {
    await pumpTool(tester);
    final long = 'https://example.test/path?x=1&y=${'v' * 40}';
    await setUrl(tester, long);
    final ctrl = tester.widget<EditableText>(inKey('http-url')).controller;
    ctrl.selection = TextSelection.collapsed(offset: long.length);
    await openTab(tester, 'Params');
    await tester.tap(find.byType(FCheckbox).at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ctrl.text, 'https://example.test/path?x=1');
    expect(ctrl.selection.isValid, isTrue);
    expect(ctrl.selection.extentOffset, lessThanOrEqualTo(ctrl.text.length));
    expect(ctrl.selection.baseOffset, greaterThanOrEqualTo(0));
  });

  testWidgets('history reload of a shorter URL keeps the caret in range',
      (tester) async {
    await startServer(tester);
    await pumpTool(tester);
    final short = '${base()}/s';
    await setUrl(tester, short);
    await sendOk(tester);
    final long = '${base()}/${'p' * 60}';
    await setUrl(tester, long);
    final ctrl = tester.widget<EditableText>(inKey('http-url')).controller;
    ctrl.selection = TextSelection.collapsed(offset: long.length);
    await tester.tap(find.byTooltip('Request history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(short));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ctrl.text, short);
    expect(ctrl.selection.isValid, isTrue);
    expect(ctrl.selection.extentOffset, short.length);
  });

  testWidgets('custom header is sent', (tester) async {
    await startServer(tester);
    await pumpTool(tester);
    await setUrl(tester, '${base()}/h');
    await openTab(tester, 'Headers');
    // fields: method select, URL, then (key, value) rows.
    final f = find.byType(EditableText);
    await tester.enterText(f.at(4), 'X-Custom');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(5), 'abc');
    await tester.pumpAndSettle();
    await sendOk(tester);
    expect(seen.single.headers.value('x-custom'), 'abc');
    expect(seen.single.headers.value('content-type'),
        startsWith('application/json'));
  });

  group('auth', () {
    Future<void> chooseAuth(WidgetTester tester, String label) async {
      await openTab(tester, 'Auth');
      await tester.tap(find.byKey(const ValueKey('http-auth-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('bearer', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await setUrl(tester, '${base()}/a');
      await chooseAuth(tester, 'Bearer Token');
      await tester.enterText(inKey('http-auth-bearer'), 'tok123');
      await sendOk(tester);
      expect(seen.single.headers.value('authorization'), 'Bearer tok123');
    });

    testWidgets('basic', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await setUrl(tester, '${base()}/a');
      await chooseAuth(tester, 'Basic Auth');
      await tester.enterText(inKey('http-auth-basic-user'), 'bob');
      await tester.enterText(inKey('http-auth-basic-pass'), 's3cret');
      await sendOk(tester);
      expect(seen.single.headers.value('authorization'),
          'Basic ${base64.encode(utf8.encode('bob:s3cret'))}');
    });

    testWidgets('api key in header', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await setUrl(tester, '${base()}/a');
      await chooseAuth(tester, 'API Key');
      await tester.enterText(inKey('http-auth-key-value'), 'k-1');
      await sendOk(tester);
      expect(seen.single.headers.value('x-api-key'), 'k-1');
      expect(seen.single.uri.queryParameters, isEmpty);
    });

    testWidgets('api key in query', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await setUrl(tester, '${base()}/a?x=1');
      await chooseAuth(tester, 'API Key');
      await tester.enterText(inKey('http-auth-key-value'), 'k-2');
      await tester.tap(find.text('Query Param'));
      await tester.pumpAndSettle();
      await sendOk(tester);
      expect(seen.single.headers.value('x-api-key'), isNull);
      expect(seen.single.uri.queryParameters, {'x': '1', 'X-API-Key': 'k-2'});
    });
  });

  group('body', () {
    testWidgets('raw JSON', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await pickMethod(tester, 'POST');
      await setUrl(tester, '${base()}/p');
      await openTab(tester, 'Body');
      await tester.enterText(inKey('http-body'), '{"k":"v"}');
      await sendOk(tester);
      final r = seen.single;
      expect(r.method, 'POST');
      expect(r.body, '{"k":"v"}');
      expect(r.headers.value('content-type'), startsWith('application/json'));
    });

    testWidgets('url encoded', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await pickMethod(tester, 'PUT');
      await setUrl(tester, '${base()}/p');
      await openTab(tester, 'Body');
      await tester.tap(find.text('URL Encoded'));
      await tester.pumpAndSettle();
      // fields: method select, URL, then the form row (key, value).
      await tester.enterText(find.byType(EditableText).at(2), 'a b');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).at(3), 'c&d');
      await tester.pumpAndSettle();
      await sendOk(tester);
      final r = seen.single;
      expect(r.method, 'PUT');
      expect(r.body, 'a+b=c%26d');
      expect(r.headers.value('content-type'),
          startsWith('application/x-www-form-urlencoded'));
    });

    testWidgets('GET sends no body', (tester) async {
      await startServer(tester);
      await pumpTool(tester);
      await setUrl(tester, '${base()}/p');
      await sendOk(tester);
      expect(seen.single.body, isEmpty);
    });
  });

  testWidgets('Enter in the URL field sends the request', (tester) async {
    await startServer(tester);
    await pumpTool(tester);
    await setUrl(tester, '${base()}/enter');
    await sendAndWait(
      tester,
      () => seen.isNotEmpty && find.byTooltip('Copy body').evaluate().isNotEmpty,
      trigger: () async {
        await tester.showKeyboard(inKey('http-url'));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      },
    );
    expect(seen.single.uri.path, '/enter');
  });

  testWidgets('history row reloads method and URL', (tester) async {
    await startServer(tester);
    await pumpTool(tester);
    await pickMethod(tester, 'DELETE');
    final url = '${base()}/h?x=1';
    await setUrl(tester, url);
    await sendOk(tester);
    expect(seen.single.method, 'DELETE');

    await pickMethod(tester, 'GET');
    await setUrl(tester, 'https://changed.test/');
    await tester.tap(find.byTooltip('Request history'));
    await tester.pumpAndSettle();
    expect(find.text('DELETE'), findsWidgets);
    await tester.tap(find.text(url));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(inKey('http-url')).controller.text, url);
    expect(find.text('No history yet'), findsNothing);
    // Panel closed; method restored in the select.
    expect(find.byTooltip('Close history'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('http-method-select')),
            matching: find.byType(EditableText)).evaluate().isNotEmpty,
        isTrue);
    final sel = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('http-method-select')),
        matching: find.byType(EditableText)));
    expect(sel.controller.text, 'DELETE');
  });

  testWidgets('non-2xx shows the error colour', (tester) async {
    await startServer(tester);
    status = 404;
    respBody = 'nope';
    await pumpTool(tester);
    await setUrl(tester, '${base()}/missing');
    await sendOk(tester);
    final t = find.text('404 Not Found');
    expect(t, findsOneWidget);
    expect(tester.widget<Text>(t).style?.color, YsColors.error);
    expect(find.text('nope'), findsOneWidget);
  });

  testWidgets('connection refused shows the error state without throwing',
      (tester) async {
    await startServer(tester);
    final closed = server.port;
    await tester.runAsync(() => server.close(force: true));
    await pumpTool(tester);
    await setUrl(tester, 'http://127.0.0.1:$closed/x');
    await sendAndWait(
        tester, () => find.text('Error').evaluate().isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('Error')).style?.color, YsColors.error);
    expect(find.textContaining('Connection refused'), findsWidgets);
    expect(find.byKey(const ValueKey('http-send')), findsOneWidget);
    // A failed request is not added to the history badge.
    await tester.tap(find.byTooltip('Request history'));
    await tester.pumpAndSettle();
    expect(find.text('No history yet'), findsOneWidget);
  });
}

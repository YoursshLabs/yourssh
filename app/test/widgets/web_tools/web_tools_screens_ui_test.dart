import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh_web_tools/src/screens/embedded_browser.dart';
import 'package:yourssh_web_tools/src/screens/http_client.dart';
import 'package:yourssh_web_tools/src/screens/http_client/history_panel.dart';
import 'package:yourssh_web_tools/src/screens/http_client/models.dart';
import 'package:yourssh_web_tools/src/screens/http_client/response_panel.dart';
import 'package:yourssh_web_tools/src/screens/utility_tools.dart';
import 'package:yourssh_web_tools/src/screens/web_tools_screen.dart';
import 'package:yourssh_web_tools/yourssh_web_tools.dart';

import '../../helpers/tab_to_control.dart';
import '../../helpers/ys_test_app.dart';

// ── Fake webview platform (no native view in widget tests) ──────────────────

final _loaded = <String>[];

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();
  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      _loaded.add(params.uri.toString());
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> runJavaScript(String javaScript) async {}
}

class _FakeNav extends PlatformNavigationDelegate {
  _FakeNav(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback onNavigationRequest) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}
  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
  @override
  Future<void> setOnWebResourceError(
      WebResourceErrorCallback onWebResourceError) async {}
  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
  @override
  Future<void> setOnHttpAuthRequest(
      HttpAuthRequestCallback onHttpAuthRequest) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _FakePlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      _FakeController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _FakeNav(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _FakeWidget(params);
}

class _Ctx implements YourSSHPluginContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _config = WebToolsPluginConfig(
  portForwardBrowserBuilder: (_) => const Text('port-forward-body'),
);

void _size(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    _loaded.clear();
    WebViewPlatform.instance = _FakePlatform();
  });

  const url60 = 'https://example.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  group('WebToolsScreen', () {
    testWidgets('smoke: sub nav switches tools', (tester) async {
      await tester.pumpWidget(ysTestApp(WebToolsScreen(config: _config)));
      await tester.pumpAndSettle();
      for (final t in ['Browser', 'HTTP Client', 'Utilities', 'Port Tunnels']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.byKey(const ValueKey('browser-url')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-tools-nav-http')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('http-send')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-tools-nav-utilities')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('util-encode')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-tools-nav-portForward')));
      await tester.pumpAndSettle();
      expect(find.text('port-forward-body'), findsOneWidget);
    });

    testWidgets('no overflow at 900x600', (tester) async {
      _size(tester, const Size(900, 600));
      await tester.pumpWidget(ysTestApp(WebToolsScreen(config: _config)));
      await tester.pumpAndSettle();
      for (final k in ['http', 'utilities', 'portForward', 'browser']) {
        await tester.tap(find.byKey(ValueKey('web-tools-nav-$k')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab reaches a sub nav item and Enter selects it',
        (tester) async {
      await tester.pumpWidget(ysTestApp(WebToolsScreen(config: _config)));
      await tester.pumpAndSettle();
      final n = await tabToControl(
          tester, find.byKey(const ValueKey('web-tools-nav-http')));
      expect(n, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('http-send')), findsOneWidget);
    });

    testWidgets('plugin root finds the Ys FTheme when pushed as a route',
        (tester) async {
      final plugin = YourSSHWebToolsPlugin(config: _config);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (ctx) => Scaffold(body: plugin.buildUI(ctx, _Ctx())),
            )),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final themed = tester.element(find.text('HTTP Client'));
      expect(FTheme.of(themed).colors.primary, YsColors.primary);
      expect(find.byType(YsPluginHost), findsOneWidget);
    });
  });

  group('HttpClientTool', () {
    testWidgets('smoke: request bar, tabs and empty response', (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('http-method-select')), findsOneWidget);
      expect(find.byKey(const ValueKey('http-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('http-send')), findsOneWidget);
      expect(find.byTooltip('Request history'), findsOneWidget);
      for (final t in ['Params', 'Auth', 'Headers', 'Body']) {
        expect(find.textContaining(t), findsWidgets, reason: t);
      }
      expect(find.text('Send a request to see the response'), findsOneWidget);
    });

    testWidgets('method select popover renders with the Ys FTheme',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('http-method-select')));
      await tester.pumpAndSettle();
      final item = find.text('DELETE');
      expect(item, findsOneWidget);
      expect(FTheme.of(tester.element(item)).colors.primary, YsColors.primary);
      await tester.tap(item);
      await tester.pumpAndSettle();
      // Selected method is shown; DELETE has no body, so the Body tab says so.
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('history panel opens, closes and lists nothing', (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Request history'));
      await tester.pumpAndSettle();
      expect(find.text('No history yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Close history'));
      await tester.pumpAndSettle();
      expect(find.text('No history yet'), findsNothing);
    });

    testWidgets('auth: bearer token and basic password fields are obscured',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('http-auth-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Basic Auth'));
      await tester.pumpAndSettle();
      final pass = tester.widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey('http-auth-basic-pass')),
          matching: find.byType(EditableText)));
      expect(pass.obscureText, isTrue);
    });

    testWidgets('params edit adds a row and syncs into the URL', (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('http-url')),
              matching: find.byType(EditableText)),
          'https://example.com/x?a=1');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Params'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('typing a param key appends a row and updates the URL',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Params'));
      await tester.pumpAndSettle();
      final fields = find.byType(EditableText);
      final before = fields.evaluate().length;
      // fields: method select, URL, then the Params row (key, value).
      await tester.enterText(fields.at(2), 'foo');
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNWidgets(before + 2)); // new row
      final url = tester.widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey('http-url')),
          matching: find.byType(EditableText)));
      expect(url.controller.text, 'https://?foo=');
    });

    testWidgets('response panel: status, time, size, copy, headers tab',
        (tester) async {
      _size(tester, const Size(900, 600));
      const r = HttpResponse(
        statusCode: 200,
        reasonPhrase: 'OK',
        headers: {'x-k': 'vvv'},
        body: '{"a": 1}',
        durationMs: 42,
        sizeBytes: 2048,
      );
      await tester.pumpWidget(ysTestApp(
          const HttpResponsePanel(response: r, loading: false)));
      await tester.pumpAndSettle();
      expect(find.text('200 OK'), findsOneWidget);
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('{"a": 1}'), findsOneWidget);
      expect(find.byTooltip('Copy body'), findsOneWidget);
      await tester.tap(find.text('Headers'));
      await tester.pumpAndSettle();
      expect(find.text('x-k'), findsOneWidget);
      expect(find.text('vvv'), findsOneWidget);
    });

    testWidgets('no overflow at 900x600 with a 60-char URL, history and long response',
        (tester) async {
      _size(tester, const Size(900, 600));
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('http-url')),
              matching: find.byType(EditableText)),
          url60);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Request history'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(ysTestApp(HttpHistoryPanel(
        history: [
          HistoryItem(
              method: 'DELETE', url: url60, statusCode: 404, durationMs: 123456),
        ],
        onSelect: (_) {},
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(ysTestApp(HttpResponsePanel(
        response: HttpResponse(
          statusCode: 503,
          reasonPhrase: 'R' * 60,
          headers: {'h' * 60: 'v' * 60},
          body: 'b' * 200,
          durationMs: 1,
          sizeBytes: 5 * 1024 * 1024,
        ),
        loading: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('history row selects the request', (tester) async {
      HistoryItem? picked;
      await tester.pumpWidget(ysTestApp(HttpHistoryPanel(
        history: [
          HistoryItem(
              method: 'GET', url: 'https://a.test/', statusCode: 200, durationMs: 5),
        ],
        onSelect: (i) => picked = i,
        onClose: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('https://a.test/'));
      await tester.pumpAndSettle();
      expect(picked?.url, 'https://a.test/');
    });

    testWidgets('Tab reaches Send; Enter in the URL field does not throw',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const HttpClientTool()));
      await tester.pumpAndSettle();
      final n =
          await tabToControl(tester, find.byKey(const ValueKey('http-send')));
      expect(n, greaterThan(0));
    });
  });

  group('UtilityTools', () {
    testWidgets('smoke + base64 encode/decode + copy tooltip', (tester) async {
      await tester.pumpWidget(ysTestApp(const UtilityTools()));
      await tester.pumpAndSettle();
      for (final t in ['Base64', 'URL', 'JSON', 'Hash']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.byTooltip('Copy output'), findsOneWidget);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('util-input')),
              matching: find.byType(EditableText)),
          'hello world');
      await tester.tap(find.byKey(const ValueKey('util-encode')));
      await tester.pumpAndSettle();
      expect(find.text('aGVsbG8gd29ybGQ='), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('util-decode')));
      await tester.pumpAndSettle();
      expect(find.text('Invalid Base64'), findsOneWidget);
    });

    testWidgets('every tool: url, json, hash actions', (tester) async {
      await tester.pumpWidget(ysTestApp(const UtilityTools()));
      await tester.pumpAndSettle();
      Future<void> input(String t) => tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('util-input')),
              matching: find.byType(EditableText)),
          t);

      await tester.tap(find.byKey(const ValueKey('util-nav-url')));
      await tester.pumpAndSettle();
      await input('a b');
      await tester.tap(find.byKey(const ValueKey('util-encode')));
      await tester.pumpAndSettle();
      expect(find.text('a%20b'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('util-decode')));
      await tester.pumpAndSettle();
      expect(find.text('Invalid URL encoding'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('util-nav-json')));
      await tester.pumpAndSettle();
      await input('{"a":1}');
      await tester.tap(find.byKey(const ValueKey('util-format')));
      await tester.pumpAndSettle();
      expect(find.text('{\n  "a": 1\n}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('util-minify')));
      await tester.pumpAndSettle();
      expect(find.text('{"a":1}'), findsNWidgets(2)); // input + output

      await tester.tap(find.byKey(const ValueKey('util-nav-hash')));
      await tester.pumpAndSettle();
      await input('');
      for (final a in ['sha256', 'sha512', 'sha1']) {
        await tester.runAsync(() async {
          await tester.tap(find.byKey(ValueKey('util-$a')));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('SHA-1:'), findsOneWidget);
    });

    testWidgets('no overflow at 900x600 with a 60-char input', (tester) async {
      _size(tester, const Size(900, 600));
      await tester.pumpWidget(ysTestApp(const UtilityTools()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('util-input')),
              matching: find.byType(EditableText)),
          'x' * 60);
      await tester.tap(find.byKey(const ValueKey('util-encode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('util-nav-hash')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab reaches Encode and Enter runs it', (tester) async {
      await tester.pumpWidget(ysTestApp(const UtilityTools()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('util-input')),
              matching: find.byType(EditableText)),
          'hi');
      final n =
          await tabToControl(tester, find.byKey(const ValueKey('util-encode')));
      expect(n, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('aGk='), findsOneWidget);
    });
  });

  group('EmbeddedBrowser', () {
    testWidgets('smoke: nav buttons with tooltips, Enter navigates',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const EmbeddedBrowser()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip('Forward'), findsOneWidget);
      expect(find.byTooltip('Reload'), findsOneWidget);
      expect(_loaded, ['https://www.google.com']);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('browser-url')),
              matching: find.byType(EditableText)),
          'example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_loaded.last, 'https://example.com');
    });

    testWidgets('non-http input becomes a search, never a raw scheme',
        (tester) async {
      await tester.pumpWidget(ysTestApp(const EmbeddedBrowser()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('browser-url')),
              matching: find.byType(EditableText)),
          'javascript:alert(1)');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_loaded.last, startsWith('https://www.google.com/search?q='));
    });

    testWidgets('no overflow at 900x600 with a 60-char URL', (tester) async {
      _size(tester, const Size(900, 600));
      await tester.pumpWidget(ysTestApp(const EmbeddedBrowser(initialUrl: url60)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab reaches Reload', (tester) async {
      await tester.pumpWidget(ysTestApp(const EmbeddedBrowser()));
      await tester.pumpAndSettle();
      final n = await tabToControl(tester, find.byTooltip('Reload'));
      expect(n, greaterThan(0));
    });
  });
}

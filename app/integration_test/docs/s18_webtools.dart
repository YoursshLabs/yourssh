// 18 Web tools against an in-test HTTP server.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '18-web-tools';

Future<void> runWebTools(JourneyContext c) async {
  final t = c.t;
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('x-demo', 'yourssh-docs');
    req.response.write(jsonEncode({
      'method': req.method,
      'path': req.uri.path,
      'query': req.uri.queryParameters,
      'body': body.isEmpty ? null : body,
      'server': 'in-test demo',
    }));
    await req.response.close();
  });
  final base = 'http://127.0.0.1:${server.port}';
  try {
    await navTo(t, 'Web Tools', wait: 1000);
    await c.snap('$s/01-web-tools', 'Web Tools: Browser / HTTP Client / Utilities / Port Tunnels');
    await step(c.notes, 'http get', () async {
      await tapKey(t, 'web-tools-nav-http', wait: 800);
      await c.snap('$s/02-http-client', 'HTTP client: method, URL, params/headers/body/auth tabs');
      await typeIntoCurrent(t, 'http', '$base/api/items?page=2&q=docs');
      await sleepPump(t, 400);
      await tapText(t, 'Send', wait: 500);
      await sleepPump(t, 2000);
      await c.snap('$s/03-get-response', 'GET with query params: pretty-printed JSON response');
      if (find.text('Headers').evaluate().isNotEmpty) {
        await tapText(t, 'Headers', index: find.text('Headers').evaluate().length - 1, wait: 600);
        await c.snap('$s/04-response-headers', 'Response headers tab');
      }
    });
    await step(c.notes, 'http post', () async {
      await tapText(t, 'GET', wait: 600);
      await c.snap('$s/05-method-menu', 'Method dropdown');
      await tapText(t, 'POST', wait: 600);
      await typeIntoCurrent(t, 'http', '$base/api/items');
      await tapText(t, 'Body', wait: 500);
      final eds = find.byType(EditableText);
      await t.enterText(eds.last, '{"name": "demo", "enabled": true}');
      await sleepPump(t, 400);
      await c.snap('$s/06-post-body', 'POST with a JSON body');
      await tapText(t, 'Send', wait: 500);
      await sleepPump(t, 2000);
      await c.snap('$s/07-post-response', 'POST response echoing the body');
    });
    await step(c.notes, 'history', () async {
      await tapTooltip(t, 'Request history', wait: 700);
      await c.snap('$s/08-history', 'Request history panel');
      await tapTooltip(t, 'Request history', wait: 500);
    });
    await step(c.notes, 'utilities', () async {
      await tapKey(t, 'web-tools-nav-utilities', wait: 800);
      await c.snap('$s/09-utilities', 'Utility tools: URL, Base64, JSON, hashes');
      await t.enterText(find.byType(EditableText).first, 'hello world & friends');
      await sleepPump(t, 300);
      await tapText(t, 'Encode', wait: 600);
      await c.snap('$s/10-url-encode', 'URL encode result');
    });
    await step(c.notes, 'browser', () async {
      await tapKey(t, 'web-tools-nav-browser', wait: 1500);
      await sleepPump(t, 2500);
      await c.snap('$s/11-browser', 'Embedded browser chrome (the native web view content is not captured by the render-tree harness)');
    });
    await step(c.notes, 'tunnels', () async {
      await tapKey(t, 'web-tools-nav-portForward', wait: 900);
      await c.snap('$s/12-port-tunnels', 'Port tunnels tab: forwards that can be opened in the browser');
    });
  } finally {
    await server.close(force: true);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yourssh/services/supabase_service.dart';

void main() {
  test('stores url and anonKey via constructor', () {
    final svc = SupabaseService('https://abc.supabase.co', 'anon-key-123');
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
  });

  group('SupabaseService.setupSchema', () {
    test('returns success when pg/query responds 200', () async {
      final svc = SupabaseService('https://abc.supabase.co', 'anon-key');
      svc.testDoPost = (_, __, ___) async => http.Response('{"result":[]}', 200);
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isTrue);
      expect(error, isNull);
    });

    test('returns success when pg/query responds 201', () async {
      final svc = SupabaseService('https://abc.supabase.co', 'anon-key');
      svc.testDoPost = (_, __, ___) async => http.Response('{}', 201);
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isTrue);
      expect(error, isNull);
    });

    test('returns failure with status code on non-200 response', () async {
      final svc = SupabaseService('https://abc.supabase.co', 'anon-key');
      svc.testDoPost = (_, __, ___) async =>
          http.Response('{"error":"unauthorized"}', 401);
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isFalse);
      expect(error, contains('401'));
    });

    test('returns failure with message on network exception', () async {
      final svc = SupabaseService('https://abc.supabase.co', 'anon-key');
      svc.testDoPost = (_, __, ___) async => throw Exception('network error');
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isFalse);
      expect(error, contains('network error'));
    });

    test('posts to correct url with service role key in headers', () async {
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;

      final svc = SupabaseService('https://abc.supabase.co', 'anon-key');
      svc.testDoPost = (uri, headers, body) async {
        capturedUri = uri;
        capturedHeaders = headers;
        return http.Response('{}', 200);
      };

      await svc.setupSchema('my-service-role-key');

      expect(capturedUri.toString(), 'https://abc.supabase.co/pg/query');
      expect(capturedHeaders['apikey'], 'my-service-role-key');
      expect(capturedHeaders['Authorization'], 'Bearer my-service-role-key');
      expect(capturedHeaders['Content-Type'], 'application/json');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TabMetadataService', () {
    test('loadMetadata returns null when no data stored', () async {
      final result = await TabMetadataService().loadMetadata('host-1');
      expect(result, isNull);
    });

    test('saveMetadata then loadMetadata round-trips all fields', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'my-prod', color: '#ef4444', pinned: true);
      final result = await svc.loadMetadata('host-1');
      expect(result?['label'], 'my-prod');
      expect(result?['color'], '#ef4444');
      expect(result?['pinned'], isTrue);
    });

    test('saveMetadata with null fields omits those keys', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: null, color: null, pinned: false);
      final result = await svc.loadMetadata('host-1');
      expect(result?['label'], isNull);
      expect(result?['color'], isNull);
      expect(result?['pinned'], isFalse);
    });

    test('saveMetadata is per-host — different hosts do not interfere', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'alpha', color: '#3b82f6', pinned: true);
      await svc.saveMetadata('host-2', label: 'beta', color: null, pinned: false);
      expect((await svc.loadMetadata('host-1'))?['label'], 'alpha');
      expect((await svc.loadMetadata('host-2'))?['label'], 'beta');
    });

    test('clearMetadata removes the stored data', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'x', color: null, pinned: false);
      await svc.clearMetadata('host-1');
      expect(await svc.loadMetadata('host-1'), isNull);
    });

    test('loadMetadata returns null for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({'tab_meta_host-1': 'not-json{{'});
      final result = await TabMetadataService().loadMetadata('host-1');
      expect(result, isNull);
    });
  });
}

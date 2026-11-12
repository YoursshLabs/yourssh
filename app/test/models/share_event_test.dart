import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/share_event.dart';

void main() {
  group('ShareEvent.fromJson', () {
    test('parses output event', () {
      final e = ShareEvent.fromJson({'type': 'output', 'data': 'hello'});
      expect(e.type, ShareEventType.output);
      expect(e.data, 'hello');
    });

    test('parses snapshot event', () {
      final e = ShareEvent.fromJson({'type': 'snapshot', 'data': 'buf'});
      expect(e.type, ShareEventType.snapshot);
    });

    test('parses snapshot_chunk event', () {
      final e = ShareEvent.fromJson({
        'type': 'snapshot_chunk',
        'data': 'chunk',
        'index': 1,
        'total': 3,
      });
      expect(e.type, ShareEventType.snapshotChunk);
      expect(e.chunkIndex, 1);
      expect(e.chunkTotal, 3);
    });

    test('parses control_grant event', () {
      final e = ShareEvent.fromJson({'type': 'control_grant', 'guestId': 'g1'});
      expect(e.type, ShareEventType.controlGrant);
      expect(e.guestId, 'g1');
    });

    test('parses ended event', () {
      final e = ShareEvent.fromJson({'type': 'ended'});
      expect(e.type, ShareEventType.ended);
    });
  });

  group('ShareEvent.toJson', () {
    test('serialises output event', () {
      final e = ShareEvent.output('hello');
      final json = e.toJson();
      expect(json['type'], 'output');
      expect(json['data'], 'hello');
    });

    test('input carries guestId', () {
      final j = ShareEvent.input('x', 'g1').toJson();
      expect(j['guestId'], 'g1');
      expect(ShareEvent.fromJson(j).guestId, 'g1');
    });
  });
}

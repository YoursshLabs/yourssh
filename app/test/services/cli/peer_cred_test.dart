import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/cli/peer_cred.dart';

Uint8List buf(int n, void Function(ByteData) fill) {
  final b = Uint8List(n);
  fill(ByteData.sublistView(b));
  return b;
}

void main() {
  test('linux ucred: uid at offset 4', () {
    final raw = buf(12, (d) {
      d.setInt32(0, 4242, Endian.host);
      d.setUint32(4, 501, Endian.host);
      d.setUint32(8, 20, Endian.host);
    });
    expect(peerUidFromCred(raw, 'linux'), 501);
  });

  test('macos xucred: uid at offset 4 when cr_version == 0', () {
    final raw = buf(76, (d) {
      d.setUint32(0, 0, Endian.host);
      d.setUint32(4, 502, Endian.host);
    });
    expect(peerUidFromCred(raw, 'macos'), 502);
  });

  test('macos xucred with wrong version returns null', () {
    final raw = buf(76, (d) {
      d.setUint32(0, 1, Endian.host);
      d.setUint32(4, 502, Endian.host);
    });
    expect(peerUidFromCred(raw, 'macos'), isNull);
  });

  test('short buffers return null', () {
    expect(peerUidFromCred(Uint8List(7), 'linux'), isNull);
    expect(peerUidFromCred(Uint8List(7), 'macos'), isNull);
  });

  test('unknown os returns null', () {
    expect(peerUidFromCred(Uint8List(76), 'windows'), isNull);
  });
}

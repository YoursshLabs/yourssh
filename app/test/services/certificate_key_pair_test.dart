import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:yourssh/services/certificate_key_pair.dart';

class _FakeKeyPair implements SSHKeyPair {
  Uint8List? lastSigned;

  @override
  String get name => 'ssh-ed25519';

  @override
  String get type => 'ssh-ed25519';

  @override
  SSHHostKey toPublicKey() => throw UnimplementedError();

  @override
  SSHSignature sign(Uint8List data) {
    lastSigned = data;
    return _FakeSignature(data);
  }

  @override
  Future<SSHSignature> signAsync(Uint8List data) async => sign(data);

  @override
  String toPem() => throw UnimplementedError();
}

class _FakeSignature implements SSHSignature {
  final Uint8List _bytes;
  _FakeSignature(this._bytes);
  @override
  Uint8List encode() => _bytes;
}

Uint8List _makeCertBlob(String algorithm) {
  final algBytes = utf8.encode(algorithm);
  final blob = Uint8List(4 + algBytes.length + 4);
  ByteData.view(blob.buffer).setUint32(0, algBytes.length, Endian.big);
  blob.setRange(4, 4 + algBytes.length, algBytes);
  return blob;
}

void main() {
  group('CertificateKeyPair', () {
    test('type reads algorithm name from cert blob', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.type, 'ssh-ed25519-cert-v01@openssh.com');
    });

    test('type works for rsa cert algorithm', () {
      final blob = _makeCertBlob('ssh-rsa-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.type, 'ssh-rsa-cert-v01@openssh.com');
    });

    test('toPublicKey encode returns cert blob verbatim', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.toPublicKey().encode(), equals(blob));
    });

    test('sign delegates to inner key pair', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final inner = _FakeKeyPair();
      final pair = CertificateKeyPair(inner, blob);
      final challenge = Uint8List.fromList([1, 2, 3]);
      pair.sign(challenge);
      expect(inner.lastSigned, equals(challenge));
    });

    test('toPem throws UnsupportedError', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(() => pair.toPem(), throwsUnsupportedError);
    });
  });
}

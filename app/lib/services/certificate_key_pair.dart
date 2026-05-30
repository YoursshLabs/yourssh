import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
// ignore: implementation_imports — SSHHostKey is not publicly exported by dartssh2.
// This will be resolved when the local fork (Task 8) exports it from lib/dartssh2.dart.
import 'package:dartssh2/src/ssh_hostkey.dart';

class CertificateKeyPair implements SSHKeyPair {
  final SSHKeyPair _inner;
  final Uint8List _certBytes;

  CertificateKeyPair(this._inner, this._certBytes) {
    if (_certBytes.length < 4) throw FormatException('Cert blob too short');
    final nameLen = ByteData.view(_certBytes.buffer, _certBytes.offsetInBytes, 4)
        .getUint32(0, Endian.big);
    if (_certBytes.length < 4 + nameLen) throw FormatException('Cert blob truncated');
  }

  static Future<CertificateKeyPair> load({
    required String keyPath,
    required String certPath,
    String? passphrase,
  }) async {
    final pem = await File(keyPath).readAsString();
    final pairs = SSHKeyPair.fromPem(pem, passphrase ?? '');
    if (pairs.isEmpty) {
      throw FormatException('No key pair found in: $keyPath (wrong passphrase?)');
    }
    final inner = pairs.first;

    final certLine = await File(certPath).readAsString();
    final parts = certLine.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw FormatException('Invalid cert file (expected "algo base64 [comment]"): $certPath');
    }
    final certBytes = base64.decode(parts[1]);
    return CertificateKeyPair(inner, certBytes);
  }

  @override
  String get name => type;

  @override
  String get type {
    final nameLen = ByteData.view(_certBytes.buffer, _certBytes.offsetInBytes, 4)
        .getUint32(0, Endian.big);
    return utf8.decode(_certBytes.sublist(4, 4 + nameLen));
  }

  @override
  SSHHostKey toPublicKey() => _RawBlobHostKey(_certBytes);

  @override
  SSHSignature sign(Uint8List data) => _inner.sign(data);

  // ignore: override_on_non_overriding_member
  Future<SSHSignature> signAsync(Uint8List data) async => _inner.sign(data);

  @override
  String toPem() => throw UnsupportedError('CertificateKeyPair cannot be serialized to PEM');
}

class _RawBlobHostKey implements SSHHostKey {
  final Uint8List _bytes;
  const _RawBlobHostKey(this._bytes);

  @override
  Uint8List encode() => _bytes;
}

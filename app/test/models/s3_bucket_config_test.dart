import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_devops/yourssh_devops.dart';

void main() {
  const config = S3BucketConfig(
    id: 'abc123',
    name: 'production',
    endpoint: 'https://s3.amazonaws.com',
    bucket: 'my-bucket',
    region: 'us-east-1',
    accessKey: 'AKIA',
    secretKey: 'secret',
  );

  test('toJson excludes secretKey', () {
    final json = config.toJson();
    expect(json['id'], 'abc123');
    expect(json['name'], 'production');
    expect(json['bucket'], 'my-bucket');
    expect(json.containsKey('secretKey'), isFalse);
  });

  test('fromJson round-trips without secretKey', () {
    final json = config.toJson();
    final restored = S3BucketConfig.fromJson(json, secretKey: 'secret');
    expect(restored.id, config.id);
    expect(restored.name, config.name);
    expect(restored.endpoint, config.endpoint);
    expect(restored.bucket, config.bucket);
    expect(restored.region, config.region);
    expect(restored.accessKey, config.accessKey);
    expect(restored.secretKey, 'secret');
  });

  test('fromJson defaults region to us-east-1 when absent', () {
    final json = config.toJson()..remove('region');
    final restored = S3BucketConfig.fromJson(json, secretKey: '');
    expect(restored.region, 'us-east-1');
  });

  test('copyWith replaces only specified fields', () {
    final updated = config.copyWith(name: 'staging', secretKey: 'newsecret');
    expect(updated.id, config.id);
    expect(updated.name, 'staging');
    expect(updated.bucket, config.bucket);
    expect(updated.secretKey, 'newsecret');
  });
}

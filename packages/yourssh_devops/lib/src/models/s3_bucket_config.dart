class S3BucketConfig {
  final String id;
  final String name;
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;

  const S3BucketConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'accessKey': accessKey,
  };

  factory S3BucketConfig.fromJson(
    Map<String, dynamic> json, {
    required String secretKey,
  }) =>
      S3BucketConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        endpoint: json['endpoint'] as String,
        bucket: json['bucket'] as String,
        region: (json['region'] as String?) ?? 'us-east-1',
        accessKey: json['accessKey'] as String,
        secretKey: secretKey,
      );

  S3BucketConfig copyWith({
    String? name,
    String? endpoint,
    String? bucket,
    String? region,
    String? accessKey,
    String? secretKey,
  }) =>
      S3BucketConfig(
        id: id,
        name: name ?? this.name,
        endpoint: endpoint ?? this.endpoint,
        bucket: bucket ?? this.bucket,
        region: region ?? this.region,
        accessKey: accessKey ?? this.accessKey,
        secretKey: secretKey ?? this.secretKey,
      );
}

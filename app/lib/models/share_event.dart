enum ShareEventType {
  output,
  input,
  snapshot,
  snapshotChunk,
  controlGrant,
  controlRevoke,
  joinRequest,
  rejected,
  ended,
}

class ShareEvent {
  final ShareEventType type;
  final String? data;
  final String? guestId;
  final int? chunkIndex;
  final int? chunkTotal;

  const ShareEvent._({
    required this.type,
    this.data,
    this.guestId,
    this.chunkIndex,
    this.chunkTotal,
  });

  factory ShareEvent.output(String data) =>
      ShareEvent._(type: ShareEventType.output, data: data);

  factory ShareEvent.input(String data) =>
      ShareEvent._(type: ShareEventType.input, data: data);

  factory ShareEvent.snapshot(String data) =>
      ShareEvent._(type: ShareEventType.snapshot, data: data);

  factory ShareEvent.snapshotChunk(String data, int index, int total) =>
      ShareEvent._(
        type: ShareEventType.snapshotChunk,
        data: data,
        chunkIndex: index,
        chunkTotal: total,
      );

  factory ShareEvent.controlGrant(String guestId) =>
      ShareEvent._(type: ShareEventType.controlGrant, guestId: guestId);

  factory ShareEvent.controlRevoke() =>
      ShareEvent._(type: ShareEventType.controlRevoke);

  factory ShareEvent.joinRequest(String guestId) =>
      ShareEvent._(type: ShareEventType.joinRequest, guestId: guestId);

  factory ShareEvent.rejected(String reason) =>
      ShareEvent._(type: ShareEventType.rejected, data: reason);

  factory ShareEvent.ended() => ShareEvent._(type: ShareEventType.ended);

  factory ShareEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = switch (typeStr) {
      'output' => ShareEventType.output,
      'input' => ShareEventType.input,
      'snapshot' => ShareEventType.snapshot,
      'snapshot_chunk' => ShareEventType.snapshotChunk,
      'control_grant' => ShareEventType.controlGrant,
      'control_revoke' => ShareEventType.controlRevoke,
      'join_request' => ShareEventType.joinRequest,
      'rejected' => ShareEventType.rejected,
      'ended' => ShareEventType.ended,
      _ => throw FormatException('Unknown ShareEvent type: $typeStr'),
    };
    return ShareEvent._(
      type: type,
      data: json['data'] as String?,
      guestId: json['guestId'] as String?,
      chunkIndex: json['index'] as int?,
      chunkTotal: json['total'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      ShareEventType.output => 'output',
      ShareEventType.input => 'input',
      ShareEventType.snapshot => 'snapshot',
      ShareEventType.snapshotChunk => 'snapshot_chunk',
      ShareEventType.controlGrant => 'control_grant',
      ShareEventType.controlRevoke => 'control_revoke',
      ShareEventType.joinRequest => 'join_request',
      ShareEventType.rejected => 'rejected',
      ShareEventType.ended => 'ended',
    };
    return {
      'type': typeStr,
      if (data != null) 'data': data,
      if (guestId != null) 'guestId': guestId,
      if (chunkIndex != null) 'index': chunkIndex,
      if (chunkTotal != null) 'total': chunkTotal,
    };
  }
}

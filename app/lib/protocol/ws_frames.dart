import 'models.dart';

/// Frames do WebSocket `/v1/ws` (PROTOCOL.md §4). Hierarquia selada por `type`.
sealed class WsFrame {
  const WsFrame();

  String get type;

  static WsFrame fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'hello' => WsHello(
        deviceId: json['device_id'] as String,
        pending: json['pending'] as int,
      ),
      'envelope' => WsEnvelope(
        Envelope.fromJson(json['envelope'] as Map<String, dynamic>),
      ),
      'ack' => WsAck((json['ids'] as List<dynamic>).cast<String>()),
      'ping' => const WsPing(),
      'pong' => const WsPong(),
      'error' => WsError(
        ApiError.fromJson(json['error'] as Map<String, dynamic>),
      ),
      _ => throw FormatException('frame WS desconhecido: $type'),
    };
  }

  Map<String, dynamic> toJson();
}

class WsHello extends WsFrame {
  const WsHello({required this.deviceId, required this.pending});

  final String deviceId;
  final int pending;

  @override
  String get type => 'hello';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'device_id': deviceId,
    'pending': pending,
  };
}

class WsEnvelope extends WsFrame {
  const WsEnvelope(this.envelope);

  final Envelope envelope;

  @override
  String get type => 'envelope';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'envelope': envelope.toJson(),
  };
}

class WsAck extends WsFrame {
  const WsAck(this.ids);

  final List<String> ids;

  @override
  String get type => 'ack';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'ids': ids};
}

class WsPing extends WsFrame {
  const WsPing();

  @override
  String get type => 'ping';

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

class WsPong extends WsFrame {
  const WsPong();

  @override
  String get type => 'pong';

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

class WsError extends WsFrame {
  const WsError(this.error);

  final ApiError error;

  @override
  String get type => 'error';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'error': error.toJson()};
}

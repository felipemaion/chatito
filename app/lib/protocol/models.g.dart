// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: json['id'] as String,
  name: json['name'] as String,
  role: $enumDecode(_$UserRoleEnumMap, json['role']),
  devices: (json['devices'] as List<dynamic>?)
      ?.map((e) => Device.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'role': _$UserRoleEnumMap[instance.role]!,
  'devices': ?instance.devices?.map((e) => e.toJson()).toList(),
};

const _$UserRoleEnumMap = {UserRole.admin: 'admin', UserRole.member: 'member'};

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String,
  userId: json['user_id'] as String?,
  name: json['name'] as String,
  platform: json['platform'] as String,
  identityKey: json['identity_key'] as String,
  createdAt: const Rfc3339Converter().fromJson(json['created_at'] as String),
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': ?instance.userId,
  'name': instance.name,
  'platform': instance.platform,
  'identity_key': instance.identityKey,
  'created_at': const Rfc3339Converter().toJson(instance.createdAt),
};

Directory _$DirectoryFromJson(Map<String, dynamic> json) => Directory(
  users: (json['users'] as List<dynamic>)
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$DirectoryToJson(Directory instance) => <String, dynamic>{
  'users': instance.users.map((e) => e.toJson()).toList(),
};

RegisterRequest _$RegisterRequestFromJson(Map<String, dynamic> json) =>
    RegisterRequest(
      inviteCode: json['invite_code'] as String,
      deviceName: json['device_name'] as String,
      platform: json['platform'] as String,
      identityKey: json['identity_key'] as String,
    );

Map<String, dynamic> _$RegisterRequestToJson(RegisterRequest instance) =>
    <String, dynamic>{
      'invite_code': instance.inviteCode,
      'device_name': instance.deviceName,
      'platform': instance.platform,
      'identity_key': instance.identityKey,
    };

RegisterResponse _$RegisterResponseFromJson(Map<String, dynamic> json) =>
    RegisterResponse(
      device: Device.fromJson(json['device'] as Map<String, dynamic>),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
    );

Map<String, dynamic> _$RegisterResponseToJson(RegisterResponse instance) =>
    <String, dynamic>{
      'device': instance.device.toJson(),
      'user': instance.user.toJson(),
      'token': instance.token,
    };

MeResponse _$MeResponseFromJson(Map<String, dynamic> json) => MeResponse(
  user: User.fromJson(json['user'] as Map<String, dynamic>),
  device: Device.fromJson(json['device'] as Map<String, dynamic>),
);

Map<String, dynamic> _$MeResponseToJson(MeResponse instance) =>
    <String, dynamic>{
      'user': instance.user.toJson(),
      'device': instance.device.toJson(),
    };

Envelope _$EnvelopeFromJson(Map<String, dynamic> json) => Envelope(
  id: json['id'] as String?,
  fromDevice: json['from_device'] as String?,
  toDevice: json['to_device'] as String,
  nonce: json['nonce'] as String,
  ciphertext: json['ciphertext'] as String,
  createdAt: _$JsonConverterFromJson<String, DateTime>(
    json['created_at'],
    const Rfc3339Converter().fromJson,
  ),
);

Map<String, dynamic> _$EnvelopeToJson(Envelope instance) => <String, dynamic>{
  'id': ?instance.id,
  'from_device': ?instance.fromDevice,
  'to_device': instance.toDevice,
  'nonce': instance.nonce,
  'ciphertext': instance.ciphertext,
  'created_at': ?_$JsonConverterToJson<String, DateTime>(
    instance.createdAt,
    const Rfc3339Converter().toJson,
  ),
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);

EnvelopesPostRequest _$EnvelopesPostRequestFromJson(
  Map<String, dynamic> json,
) => EnvelopesPostRequest(
  envelopes: (json['envelopes'] as List<dynamic>)
      .map((e) => Envelope.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$EnvelopesPostRequestToJson(
  EnvelopesPostRequest instance,
) => <String, dynamic>{
  'envelopes': instance.envelopes.map((e) => e.toJson()).toList(),
};

AcceptedEnvelope _$AcceptedEnvelopeFromJson(Map<String, dynamic> json) =>
    AcceptedEnvelope(
      id: json['id'] as String,
      toDevice: json['to_device'] as String,
    );

Map<String, dynamic> _$AcceptedEnvelopeToJson(AcceptedEnvelope instance) =>
    <String, dynamic>{'id': instance.id, 'to_device': instance.toDevice};

EnvelopesPostResponse _$EnvelopesPostResponseFromJson(
  Map<String, dynamic> json,
) => EnvelopesPostResponse(
  accepted: (json['accepted'] as List<dynamic>)
      .map((e) => AcceptedEnvelope.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$EnvelopesPostResponseToJson(
  EnvelopesPostResponse instance,
) => <String, dynamic>{
  'accepted': instance.accepted.map((e) => e.toJson()).toList(),
};

EnvelopesListResponse _$EnvelopesListResponseFromJson(
  Map<String, dynamic> json,
) => EnvelopesListResponse(
  envelopes: (json['envelopes'] as List<dynamic>)
      .map((e) => Envelope.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$EnvelopesListResponseToJson(
  EnvelopesListResponse instance,
) => <String, dynamic>{
  'envelopes': instance.envelopes.map((e) => e.toJson()).toList(),
};

AckRequest _$AckRequestFromJson(Map<String, dynamic> json) => AckRequest(
  ids: (json['ids'] as List<dynamic>).map((e) => e as String).toList(),
);

Map<String, dynamic> _$AckRequestToJson(AckRequest instance) =>
    <String, dynamic>{'ids': instance.ids};

PushTokenRequest _$PushTokenRequestFromJson(Map<String, dynamic> json) =>
    PushTokenRequest(fcmToken: json['fcm_token'] as String?);

Map<String, dynamic> _$PushTokenRequestToJson(PushTokenRequest instance) =>
    <String, dynamic>{'fcm_token': instance.fcmToken};

ApiError _$ApiErrorFromJson(Map<String, dynamic> json) =>
    ApiError(code: json['code'] as String, message: json['message'] as String);

Map<String, dynamic> _$ApiErrorToJson(ApiError instance) => <String, dynamic>{
  'code': instance.code,
  'message': instance.message,
};

ErrorResponse _$ErrorResponseFromJson(Map<String, dynamic> json) =>
    ErrorResponse(
      error: ApiError.fromJson(json['error'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ErrorResponseToJson(ErrorResponse instance) =>
    <String, dynamic>{'error': instance.error.toJson()};

BlobCreateRequest _$BlobCreateRequestFromJson(Map<String, dynamic> json) =>
    BlobCreateRequest(
      size: (json['size'] as num).toInt(),
      recipients: (json['recipients'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$BlobCreateRequestToJson(BlobCreateRequest instance) =>
    <String, dynamic>{'size': instance.size, 'recipients': instance.recipients};

BlobCreateResponse _$BlobCreateResponseFromJson(Map<String, dynamic> json) =>
    BlobCreateResponse(
      blobId: json['blob_id'] as String,
      chunkSize: (json['chunk_size'] as num).toInt(),
      expiresAt: const Rfc3339Converter().fromJson(
        json['expires_at'] as String,
      ),
    );

Map<String, dynamic> _$BlobCreateResponseToJson(BlobCreateResponse instance) =>
    <String, dynamic>{
      'blob_id': instance.blobId,
      'chunk_size': instance.chunkSize,
      'expires_at': const Rfc3339Converter().toJson(instance.expiresAt),
    };

BlobCompleteResponse _$BlobCompleteResponseFromJson(
  Map<String, dynamic> json,
) => BlobCompleteResponse(
  blobId: json['blob_id'] as String,
  size: (json['size'] as num).toInt(),
);

Map<String, dynamic> _$BlobCompleteResponseToJson(
  BlobCompleteResponse instance,
) => <String, dynamic>{'blob_id': instance.blobId, 'size': instance.size};

InviteRequest _$InviteRequestFromJson(Map<String, dynamic> json) =>
    InviteRequest(
      userName: json['user_name'] as String?,
      userId: json['user_id'] as String?,
    );

Map<String, dynamic> _$InviteRequestToJson(InviteRequest instance) =>
    <String, dynamic>{
      'user_name': ?instance.userName,
      'user_id': ?instance.userId,
    };

InviteResponse _$InviteResponseFromJson(Map<String, dynamic> json) =>
    InviteResponse(
      code: json['code'] as String,
      userId: json['user_id'] as String,
      expiresAt: const Rfc3339Converter().fromJson(
        json['expires_at'] as String,
      ),
    );

Map<String, dynamic> _$InviteResponseToJson(InviteResponse instance) =>
    <String, dynamic>{
      'code': instance.code,
      'user_id': instance.userId,
      'expires_at': const Rfc3339Converter().toJson(instance.expiresAt),
    };

RoleRequest _$RoleRequestFromJson(Map<String, dynamic> json) =>
    RoleRequest(role: $enumDecode(_$UserRoleEnumMap, json['role']));

Map<String, dynamic> _$RoleRequestToJson(RoleRequest instance) =>
    <String, dynamic>{'role': _$UserRoleEnumMap[instance.role]!};

Attachment _$AttachmentFromJson(Map<String, dynamic> json) => Attachment(
  blobId: json['blob_id'] as String,
  name: json['name'] as String,
  size: (json['size'] as num).toInt(),
  mime: json['mime'] as String,
  key: json['key'] as String,
  header: json['header'] as String,
  chunkSize: (json['chunk_size'] as num?)?.toInt() ?? 65536,
);

Map<String, dynamic> _$AttachmentToJson(Attachment instance) =>
    <String, dynamic>{
      'blob_id': instance.blobId,
      'name': instance.name,
      'size': instance.size,
      'mime': instance.mime,
      'key': instance.key,
      'header': instance.header,
      'chunk_size': instance.chunkSize,
    };

Receipt _$ReceiptFromJson(Map<String, dynamic> json) => Receipt(
  msgId: json['msg_id'] as String,
  status: $enumDecode(_$ReceiptStatusEnumMap, json['status']),
);

Map<String, dynamic> _$ReceiptToJson(Receipt instance) => <String, dynamic>{
  'msg_id': instance.msgId,
  'status': _$ReceiptStatusEnumMap[instance.status]!,
};

const _$ReceiptStatusEnumMap = {
  ReceiptStatus.delivered: 'delivered',
  ReceiptStatus.read: 'read',
};

Payload _$PayloadFromJson(Map<String, dynamic> json) => Payload(
  v: (json['v'] as num?)?.toInt() ?? 1,
  msgId: json['msg_id'] as String,
  convId: json['conv_id'] as String,
  kind: $enumDecode(_$PayloadKindEnumMap, json['kind']),
  sentAt: const Rfc3339Converter().fromJson(json['sent_at'] as String),
  body: json['body'] as String?,
  attachments: (json['attachments'] as List<dynamic>?)
      ?.map((e) => Attachment.fromJson(e as Map<String, dynamic>))
      .toList(),
  receipt: json['receipt'] == null
      ? null
      : Receipt.fromJson(json['receipt'] as Map<String, dynamic>),
);

Map<String, dynamic> _$PayloadToJson(Payload instance) => <String, dynamic>{
  'v': instance.v,
  'msg_id': instance.msgId,
  'conv_id': instance.convId,
  'kind': _$PayloadKindEnumMap[instance.kind]!,
  'sent_at': const Rfc3339Converter().toJson(instance.sentAt),
  'body': ?instance.body,
  'attachments': ?instance.attachments?.map((e) => e.toJson()).toList(),
  'receipt': ?instance.receipt?.toJson(),
};

const _$PayloadKindEnumMap = {
  PayloadKind.text: 'text',
  PayloadKind.file: 'file',
  PayloadKind.receipt: 'receipt',
  PayloadKind.keyChange: 'key_change',
};

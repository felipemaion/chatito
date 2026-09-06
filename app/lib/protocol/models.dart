import 'package:json_annotation/json_annotation.dart';

import 'json_util.dart';

part 'models.g.dart';

enum UserRole { admin, member }

enum PayloadKind {
  text,
  file,
  receipt,
  @JsonValue('key_change')
  keyChange,
}

enum ReceiptStatus { delivered, read }

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class User {
  User({
    required this.id,
    required this.name,
    required this.role,
    this.devices,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  final String id;
  final String name;
  final UserRole role;

  /// Presente só em `GET /v1/directory`.
  final List<Device>? devices;

  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Device {
  Device({
    required this.id,
    this.userId,
    required this.name,
    required this.platform,
    required this.identityKey,
    required this.createdAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);

  final String id;

  /// Ausente dentro de `directory.users[].devices[]` (implícito pelo pai).
  final String? userId;
  final String name;
  final String platform;

  /// X25519 pública, base64 padrão.
  final String identityKey;
  @Rfc3339Converter()
  final DateTime createdAt;

  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Directory {
  Directory({required this.users});

  factory Directory.fromJson(Map<String, dynamic> json) =>
      _$DirectoryFromJson(json);

  final List<User> users;

  Map<String, dynamic> toJson() => _$DirectoryToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class RegisterRequest {
  RegisterRequest({
    required this.inviteCode,
    required this.deviceName,
    required this.platform,
    required this.identityKey,
  });

  factory RegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestFromJson(json);

  final String inviteCode;
  final String deviceName;
  final String platform;
  final String identityKey;

  Map<String, dynamic> toJson() => _$RegisterRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class RegisterResponse {
  RegisterResponse({
    required this.device,
    required this.user,
    required this.token,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      _$RegisterResponseFromJson(json);

  final Device device;
  final User user;

  /// Bearer token — entregue uma única vez.
  final String token;

  Map<String, dynamic> toJson() => _$RegisterResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class MeResponse {
  MeResponse({required this.user, required this.device});

  factory MeResponse.fromJson(Map<String, dynamic> json) =>
      _$MeResponseFromJson(json);

  final User user;
  final Device device;

  Map<String, dynamic> toJson() => _$MeResponseToJson(this);
}

/// Envelope cifrado. No `POST /v1/envelopes` só `to_device`, `nonce` e
/// `ciphertext` vão; o servidor preenche `id`, `from_device` e `created_at`.
@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Envelope {
  Envelope({
    this.id,
    this.fromDevice,
    required this.toDevice,
    required this.nonce,
    required this.ciphertext,
    this.createdAt,
  });

  factory Envelope.fromJson(Map<String, dynamic> json) =>
      _$EnvelopeFromJson(json);

  final String? id;
  final String? fromDevice;
  final String toDevice;

  /// 24 bytes, base64.
  final String nonce;

  /// `crypto_box_easy`, base64, ≤ 64 KiB.
  final String ciphertext;
  @Rfc3339Converter()
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => _$EnvelopeToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class EnvelopesPostRequest {
  EnvelopesPostRequest({required this.envelopes});

  factory EnvelopesPostRequest.fromJson(Map<String, dynamic> json) =>
      _$EnvelopesPostRequestFromJson(json);

  final List<Envelope> envelopes;

  Map<String, dynamic> toJson() => _$EnvelopesPostRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AcceptedEnvelope {
  AcceptedEnvelope({required this.id, required this.toDevice});

  factory AcceptedEnvelope.fromJson(Map<String, dynamic> json) =>
      _$AcceptedEnvelopeFromJson(json);

  final String id;
  final String toDevice;

  Map<String, dynamic> toJson() => _$AcceptedEnvelopeToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class EnvelopesPostResponse {
  EnvelopesPostResponse({required this.accepted});

  factory EnvelopesPostResponse.fromJson(Map<String, dynamic> json) =>
      _$EnvelopesPostResponseFromJson(json);

  final List<AcceptedEnvelope> accepted;

  Map<String, dynamic> toJson() => _$EnvelopesPostResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class EnvelopesListResponse {
  EnvelopesListResponse({required this.envelopes});

  factory EnvelopesListResponse.fromJson(Map<String, dynamic> json) =>
      _$EnvelopesListResponseFromJson(json);

  final List<Envelope> envelopes;

  Map<String, dynamic> toJson() => _$EnvelopesListResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AckRequest {
  AckRequest({required this.ids});

  factory AckRequest.fromJson(Map<String, dynamic> json) =>
      _$AckRequestFromJson(json);

  final List<String> ids;

  Map<String, dynamic> toJson() => _$AckRequestToJson(this);
}

/// `{"fcm_token": null}` desregistra — por isso `includeIfNull` fica ligado aqui.
@JsonSerializable(fieldRename: FieldRename.snake)
class PushTokenRequest {
  PushTokenRequest({required this.fcmToken});

  factory PushTokenRequest.fromJson(Map<String, dynamic> json) =>
      _$PushTokenRequestFromJson(json);

  final String? fcmToken;

  Map<String, dynamic> toJson() => _$PushTokenRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ApiError {
  ApiError({required this.code, required this.message});

  factory ApiError.fromJson(Map<String, dynamic> json) =>
      _$ApiErrorFromJson(json);

  final String code;
  final String message;

  Map<String, dynamic> toJson() => _$ApiErrorToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class ErrorResponse {
  ErrorResponse({required this.error});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  final ApiError error;

  Map<String, dynamic> toJson() => _$ErrorResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class BlobCreateRequest {
  BlobCreateRequest({required this.size, required this.recipients});

  factory BlobCreateRequest.fromJson(Map<String, dynamic> json) =>
      _$BlobCreateRequestFromJson(json);

  final int size;
  final List<String> recipients;

  Map<String, dynamic> toJson() => _$BlobCreateRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class BlobCreateResponse {
  BlobCreateResponse({
    required this.blobId,
    required this.chunkSize,
    required this.expiresAt,
  });

  factory BlobCreateResponse.fromJson(Map<String, dynamic> json) =>
      _$BlobCreateResponseFromJson(json);

  final String blobId;
  final int chunkSize;
  @Rfc3339Converter()
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => _$BlobCreateResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class BlobCompleteResponse {
  BlobCompleteResponse({required this.blobId, required this.size});

  factory BlobCompleteResponse.fromJson(Map<String, dynamic> json) =>
      _$BlobCompleteResponseFromJson(json);

  final String blobId;
  final int size;

  Map<String, dynamic> toJson() => _$BlobCompleteResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class InviteRequest {
  InviteRequest({this.userName, this.userId});

  factory InviteRequest.fromJson(Map<String, dynamic> json) =>
      _$InviteRequestFromJson(json);

  final String? userName;
  final String? userId;

  Map<String, dynamic> toJson() => _$InviteRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class InviteResponse {
  InviteResponse({
    required this.code,
    required this.userId,
    required this.expiresAt,
  });

  factory InviteResponse.fromJson(Map<String, dynamic> json) =>
      _$InviteResponseFromJson(json);

  final String code;
  final String userId;
  @Rfc3339Converter()
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => _$InviteResponseToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class RoleRequest {
  RoleRequest({required this.role});

  factory RoleRequest.fromJson(Map<String, dynamic> json) =>
      _$RoleRequestFromJson(json);

  final UserRole role;

  Map<String, dynamic> toJson() => _$RoleRequestToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Attachment {
  Attachment({
    required this.blobId,
    required this.name,
    required this.size,
    required this.mime,
    required this.key,
    required this.header,
    this.chunkSize = 65536,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  final String blobId;
  final String name;
  final int size;
  final String mime;

  /// Chave secretstream (32 B), base64.
  final String key;

  /// Header secretstream (24 B), base64.
  final String header;
  final int chunkSize;

  Map<String, dynamic> toJson() => _$AttachmentToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Receipt {
  Receipt({required this.msgId, required this.status});

  factory Receipt.fromJson(Map<String, dynamic> json) =>
      _$ReceiptFromJson(json);

  final String msgId;
  final ReceiptStatus status;

  Map<String, dynamic> toJson() => _$ReceiptToJson(this);
}

/// Payload decifrado (PROTOCOL.md §5). Campos desconhecidos são ignorados.
@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Payload {
  Payload({
    this.v = 1,
    required this.msgId,
    required this.convId,
    required this.kind,
    required this.sentAt,
    this.body,
    this.attachments,
    this.receipt,
  });

  factory Payload.fromJson(Map<String, dynamic> json) =>
      _$PayloadFromJson(json);

  final int v;
  final String msgId;
  final String convId;
  final PayloadKind kind;
  @Rfc3339Converter()
  final DateTime sentAt;
  final String? body;
  final List<Attachment>? attachments;
  final Receipt? receipt;

  Map<String, dynamic> toJson() => _$PayloadToJson(this);
}

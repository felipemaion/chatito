import 'package:drift/drift.dart';

@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DeviceRow')
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  TextColumn get identityKey => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ConversationRow')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();

  /// user_ids separados por `,`.
  TextColumn get participants => text()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  TextColumn get lastMessageId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MessageRow')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get convId => text()();
  TextColumn get senderUserId => text()();
  TextColumn get senderDeviceId => text()();
  TextColumn get kind => text()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get sentAt => dateTime()();
  BoolColumn get isMine => boolean()();
  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get blobId => text()();
  TextColumn get messageId => text()();
  TextColumn get name => text()();
  IntColumn get size => integer()();
  TextColumn get mime => text()();
  BlobColumn get key => blob()();
  BlobColumn get header => blob()();
  IntColumn get chunkSize => integer()();
  TextColumn get localPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {blobId};
}

/// Envelopes cifrados aguardando `POST /v1/envelopes`.
@DataClassName('OutboxRow')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get msgId => text()();
  TextColumn get toDevice => text()();
  TextColumn get nonce => text()();
  TextColumn get ciphertext => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

import 'dart:convert';

import '../../crypto/crypto.dart';
import '../../protocol/protocol.dart';
import '../../storage/storage.dart';
import '../../transport/transport.dart';
import '../models.dart';

/// Sessão ativa: quem sou + minhas chaves.
class ActiveSession {
  const ActiveSession({
    required this.user,
    required this.device,
    required this.keys,
  });

  final User user;
  final Device device;
  final IdentityKeyPair keys;

  Registered get asState => Registered(user: user, device: device);
}

/// Dependências compartilhadas pelos casos de uso.
class ChatContext {
  ChatContext({
    required this.cryptoBox,
    required this.fileCipher,
    required this.db,
    required this.keyStore,
    required this.api,
    required this.log,
    required this.now,
    required this.newId,
  });

  final CryptoBox cryptoBox;
  final FileCipher fileCipher;
  final ChatDatabase db;
  final KeyStore keyStore;
  final RelayApi api;
  final void Function(String message) log;
  final DateTime Function() now;
  final String Function() newId;

  /// Converte erros das camadas de baixo em [ChatException].
  static Never rethrowAsChat(Object e) {
    if (e is ChatException) {
      throw e;
    }
    if (e is RelayException) {
      throw ChatException(e.code, e.message);
    }
    if (e is CryptoFailure) {
      throw ChatException('crypto', e.message);
    }
    if (e is ArgumentError) {
      throw ChatException('validation', e.message.toString());
    }
    throw ChatException('internal', e.toString());
  }

  static Future<T> guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (e) {
      rethrowAsChat(e);
    }
  }

  List<int> encodePayload(Payload p) => utf8.encode(jsonEncode(p.toJson()));

  Payload decodePayload(List<int> bytes) =>
      Payload.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
}

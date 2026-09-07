import 'dart:typed_data';

/// Falha criptográfica (MAC inválido, tamanho errado, stream truncado…).
/// Nunca expõe detalhes que ajudem um atacante; apenas contexto para log.
class CryptoFailure implements Exception {
  const CryptoFailure(this.message);

  final String message;

  @override
  String toString() => 'CryptoFailure: $message';
}

/// Par X25519 do device. `secretKey` fica só no [KeyStore].
class IdentityKeyPair {
  const IdentityKeyPair({required this.publicKey, required this.secretKey});

  final Uint8List publicKey;
  final Uint8List secretKey;
}

class SealedBox {
  const SealedBox({required this.nonce, required this.ciphertext});

  /// 24 bytes.
  final Uint8List nonce;
  final Uint8List ciphertext;
}

/// `crypto_box_easy` / `crypto_box_open_easy` + safety number.
abstract interface class CryptoBox {
  static const publicKeyBytes = 32;
  static const secretKeyBytes = 32;
  static const nonceBytes = 24;
  static const macBytes = 16;

  IdentityKeyPair generateKeyPair();

  /// [nonce] aleatório se omitido (uso normal); explícito só para vetores de teste.
  SealedBox seal({
    required List<int> plaintext,
    required Uint8List recipientPk,
    required Uint8List senderSk,
    Uint8List? nonce,
  });

  /// Lança [CryptoFailure] se o MAC não validar com `senderPk`.
  Uint8List open({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List senderPk,
    required Uint8List recipientSk,
  });

  /// 60 dígitos decimais, simétrico (PROTOCOL.md §2, `safety_number_rule`).
  String safetyNumber(Uint8List pkA, Uint8List pkB);
}

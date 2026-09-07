import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:sodium/sodium.dart';

import 'crypto_box.dart';

class SodiumCryptoBox implements CryptoBox {
  SodiumCryptoBox(this._sodium);

  final Sodium _sodium;

  Box get _box => _sodium.crypto.box;

  @override
  IdentityKeyPair generateKeyPair() {
    final kp = _box.keyPair();
    try {
      return IdentityKeyPair(
        publicKey: kp.publicKey,
        secretKey: kp.secretKey.extractBytes(),
      );
    } finally {
      kp.dispose();
    }
  }

  @override
  SealedBox seal({
    required List<int> plaintext,
    required Uint8List recipientPk,
    required Uint8List senderSk,
    Uint8List? nonce,
  }) {
    final n = nonce ?? _sodium.randombytes.buf(CryptoBox.nonceBytes);
    final sk = _secure(senderSk);
    try {
      final ct = _box.easy(
        message: plaintext is Uint8List
            ? plaintext
            : Uint8List.fromList(plaintext),
        nonce: n,
        publicKey: recipientPk,
        secretKey: sk,
      );
      return SealedBox(nonce: n, ciphertext: ct);
    } on SodiumException catch (e) {
      throw CryptoFailure('seal: $e');
    } on RangeError catch (e) {
      throw CryptoFailure('seal: $e');
    } finally {
      sk.dispose();
    }
  }

  @override
  Uint8List open({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required Uint8List senderPk,
    required Uint8List recipientSk,
  }) {
    final sk = _secure(recipientSk);
    try {
      return _box.openEasy(
        cipherText: ciphertext,
        nonce: nonce,
        publicKey: senderPk,
        secretKey: sk,
      );
    } on SodiumException catch (e) {
      throw CryptoFailure('open: $e');
    } on RangeError catch (e) {
      throw CryptoFailure('open: $e');
    } finally {
      sk.dispose();
    }
  }

  @override
  String safetyNumber(Uint8List pkA, Uint8List pkB) {
    final first = _compare(pkA, pkB) <= 0 ? pkA : pkB;
    final second = identical(first, pkA) ? pkB : pkA;
    final h = sha256.convert([...first, ...second]).bytes;
    final buf = StringBuffer();
    for (var i = 0; i < 12; i++) {
      var v = 0;
      for (var j = 0; j < 5; j++) {
        v = (v << 8) | h[(5 * i + j) % 32];
      }
      buf.write((v % 100000).toString().padLeft(5, '0'));
    }
    return buf.toString();
  }

  SecureKey _secure(Uint8List bytes) => _sodium.secureCopy(bytes);

  static int _compare(Uint8List a, Uint8List b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}

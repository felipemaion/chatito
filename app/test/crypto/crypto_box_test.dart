import 'dart:convert';
import 'dart:typed_data';

import 'package:chatito/crypto/crypto.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';
import '../support/sodium.dart';

void main() {
  late CryptoBox box;
  late Map<String, dynamic> v;
  Uint8List b64(String k) => base64.decode(v[k] as String);

  setUpAll(() async {
    box = SodiumCryptoBox(await loadSodium());
    v = loadFixture('crypto_box_vector');
  });

  group('crypto_box_vector.json', () {
    test('seal reproduz o ciphertext do vetor', () {
      final sealed = box.seal(
        plaintext: utf8.encode(v['plaintext_utf8'] as String),
        recipientPk: b64('recipient_pk'),
        senderSk: b64('sender_sk'),
        nonce: b64('nonce'),
      );
      expect(base64.encode(sealed.ciphertext), v['ciphertext']);
      expect(sealed.nonce, b64('nonce'));
    });

    test('open decifra o ciphertext do vetor', () {
      final plain = box.open(
        ciphertext: b64('ciphertext'),
        nonce: b64('nonce'),
        senderPk: b64('sender_pk'),
        recipientSk: b64('recipient_sk'),
      );
      expect(utf8.decode(plain), v['plaintext_utf8']);
    });

    test('safety number igual ao vetor e simétrico', () {
      final a = b64('sender_pk');
      final b = b64('recipient_pk');
      expect(box.safetyNumber(a, b), v['safety_number']);
      expect(box.safetyNumber(b, a), v['safety_number']);
      expect(box.safetyNumber(a, b), hasLength(60));
    });
  });

  group('operação normal', () {
    test('keypair novo: 32 B cada, round-trip com nonce aleatório', () {
      final alice = box.generateKeyPair();
      final bob = box.generateKeyPair();
      expect(alice.publicKey, hasLength(32));
      expect(alice.secretKey, hasLength(32));
      expect(alice.publicKey, isNot(bob.publicKey));

      final msg = utf8.encode('olá');
      final sealed = box.seal(
        plaintext: msg,
        recipientPk: bob.publicKey,
        senderSk: alice.secretKey,
      );
      expect(sealed.nonce, hasLength(24));
      expect(sealed.ciphertext, hasLength(msg.length + 16));
      final again = box.seal(
        plaintext: msg,
        recipientPk: bob.publicKey,
        senderSk: alice.secretKey,
      );
      expect(
        again.nonce,
        isNot(sealed.nonce),
        reason: 'nonce aleatório por mensagem',
      );

      final plain = box.open(
        ciphertext: sealed.ciphertext,
        nonce: sealed.nonce,
        senderPk: alice.publicKey,
        recipientSk: bob.secretKey,
      );
      expect(plain, msg);
    });

    test('MAC inválido (bit trocado / chave errada) lança CryptoFailure', () {
      final alice = box.generateKeyPair();
      final bob = box.generateKeyPair();
      final eve = box.generateKeyPair();
      final sealed = box.seal(
        plaintext: utf8.encode('x'),
        recipientPk: bob.publicKey,
        senderSk: alice.secretKey,
      );
      final tampered = Uint8List.fromList(sealed.ciphertext)..[0] ^= 1;
      expect(
        () => box.open(
          ciphertext: tampered,
          nonce: sealed.nonce,
          senderPk: alice.publicKey,
          recipientSk: bob.secretKey,
        ),
        throwsA(isA<CryptoFailure>()),
      );
      expect(
        () => box.open(
          ciphertext: sealed.ciphertext,
          nonce: sealed.nonce,
          senderPk: eve.publicKey,
          recipientSk: bob.secretKey,
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('tamanhos inválidos de chave/nonce lançam CryptoFailure', () {
      final kp = box.generateKeyPair();
      expect(
        () => box.seal(
          plaintext: Uint8List(1),
          recipientPk: Uint8List(5),
          senderSk: kp.secretKey,
        ),
        throwsA(isA<CryptoFailure>()),
      );
      expect(
        () => box.seal(
          plaintext: Uint8List(1),
          recipientPk: kp.publicKey,
          senderSk: kp.secretKey,
          nonce: Uint8List(3),
        ),
        throwsA(isA<CryptoFailure>()),
      );
      expect(const CryptoFailure('x').toString(), contains('x'));
    });
  });
}

import 'package:piriquito/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ConvId', () {
    test('1:1 ordena os user_ids lexicograficamente', () {
      expect(
        ConvId.direct(
          'usr_Ym9iYm9iYm9iYm9iYm9iYjI',
          'usr_YWxpY2VhbGljZWFsaWNlMQ',
        ),
        'u:usr_YWxpY2VhbGljZWFsaWNlMQ:usr_Ym9iYm9iYm9iYm9iYm9iYjI',
      );
      expect(ConvId.direct('usr_a', 'usr_b'), ConvId.direct('usr_b', 'usr_a'));
    });

    test('grupo único v1', () {
      expect(ConvId.family, 'g:familia');
      expect(ConvId.isGroup('g:familia'), isTrue);
      expect(ConvId.isGroup('u:usr_a:usr_b'), isFalse);
    });

    test('participantes de 1:1', () {
      expect(ConvId.directParticipants('u:usr_a:usr_b'), ['usr_a', 'usr_b']);
      expect(ConvId.directParticipants('g:familia'), isNull);
    });

    test('peer de um 1:1 dado o próprio id', () {
      expect(ConvId.peerOf('u:usr_a:usr_b', 'usr_a'), 'usr_b');
      expect(ConvId.peerOf('u:usr_a:usr_b', 'usr_b'), 'usr_a');
      expect(ConvId.peerOf('g:familia', 'usr_a'), isNull);
    });
  });
}

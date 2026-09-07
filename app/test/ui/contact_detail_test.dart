import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/qr_scanner.dart';
import 'package:chatito/ui/screens/contact_detail_screen.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers.dart';

class _FakeScanner implements QrScannerService {
  _FakeScanner(this.result);
  final String? result;
  @override
  bool get isSupported => true;
  @override
  Future<String?> scan(BuildContext context) async => result;
}

FakeChatFacade _seeded() => FakeChatFacade(autoReplyDelay: Duration.zero);

void main() {
  testWidgets('mostra nome, aparelhos e safety number com QR', (tester) async {
    final f = _seeded();
    await pumpScreen(
      tester,
      const ContactDetailScreen(userId: FakeChatFacade.maeId),
      facade: f,
    );
    expect(find.text('Mãe'), findsWidgets);
    expect(find.text('Galaxy'), findsOneWidget);
    final sn = await f.safetyNumber(FakeChatFacade.maeDeviceId);
    expect(find.text(sn.formatted), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('QR lido igual → conferem; diferente → não conferem', (
    tester,
  ) async {
    final f = _seeded();
    final sn = await f.safetyNumber(FakeChatFacade.maeDeviceId);
    await pumpScreen(
      tester,
      const ContactDetailScreen(userId: FakeChatFacade.maeId),
      facade: f,
      overrides: [
        qrScannerProvider.overrideWithValue(_FakeScanner(sn.formatted)),
      ],
    );
    await tester.tap(
      find.byKey(const Key('scan-${FakeChatFacade.maeDeviceId}')),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.verified), findsOneWidget);

    await pumpScreen(
      tester,
      const ContactDetailScreen(userId: FakeChatFacade.maeId),
      facade: f,
      overrides: [
        qrScannerProvider.overrideWithValue(_FakeScanner('00000 11111')),
      ],
    );
    await tester.tap(
      find.byKey(const Key('scan-${FakeChatFacade.maeDeviceId}')),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.notVerified), findsOneWidget);
  });

  testWidgets('botão abre a conversa 1:1', (tester) async {
    await pumpApp(
      tester,
      size: phoneSize,
      initialLocation: '/contact/${FakeChatFacade.maeId}',
    );
    await tester.tap(find.byKey(const Key('open-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat')), findsOneWidget);
    expect(
      find.text('Cheguei sim, filho. Foto da praia depois!'),
      findsOneWidget,
    );
  });

  testWidgets('usuário desconhecido mostra aviso', (tester) async {
    await pumpScreen(tester, const ContactDetailScreen(userId: 'usr_nope'));
    expect(find.byKey(const Key('contact-missing')), findsOneWidget);
  });
}

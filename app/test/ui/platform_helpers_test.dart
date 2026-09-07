import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/files.dart';
import 'package:chatito/platform/platform_info.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/strings.dart';
import 'package:chatito/ui/widgets/connection_banner.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('mimeFromName cobre extensões comuns', () {
    expect(mimeFromName('a.JPG'), 'image/jpeg');
    expect(mimeFromName('a.png'), 'image/png');
    expect(mimeFromName('doc.pdf'), 'application/pdf');
    expect(mimeFromName('semext'), 'application/octet-stream');
  });

  test('PlatformInfo sugere nome por plataforma e detecta o host', () {
    const mac = PlatformInfo(name: 'macos', isDesktop: true, isAndroid: false);
    const and = PlatformInfo(
      name: 'android',
      isDesktop: false,
      isAndroid: true,
    );
    const other = PlatformInfo(
      name: 'linux',
      isDesktop: true,
      isAndroid: false,
    );
    expect(mac.defaultDeviceName, 'Mac');
    expect(and.defaultDeviceName, 'Android');
    expect(other.defaultDeviceName, 'linux');
    final host = PlatformInfo.detect();
    expect(host.name, isNotEmpty);
    expect(host.isDesktop || host.isAndroid || host.name == 'web', isTrue);
  });

  test('FirebasePushWaker.isWake', () {
    expect(FirebasePushWaker.isWake({'type': 'wake'}), isTrue);
    expect(FirebasePushWaker.isWake({'type': 'other'}), isFalse);
    expect(FirebasePushWaker.isWake({}), isFalse);
  });

  testWidgets('ConnectionBanner some quando conectado', (tester) async {
    final f = FakeChatFacade(autoReplyDelay: Duration.zero);
    await pumpScreen(
      tester,
      const Scaffold(body: ConnectionBanner()),
      facade: f,
    );
    // Estado inicial da fake é offline (antes de `connect()`).
    expect(find.text(S.offline), findsOneWidget);
    await f.connect();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connection-banner')), findsNothing);
  });

  testWidgets('conversa mostra faixa de offline por padrão', (tester) async {
    await pumpApp(tester, size: phoneSize);
    expect(find.byKey(const Key('connection-banner')), findsOneWidget);
  });

  testWidgets('botão Reconectar da faixa de conexão chama connect()', (
    tester,
  ) async {
    final f = FakeChatFacade(autoReplyDelay: Duration.zero);
    await pumpScreen(
      tester,
      const Scaffold(body: ConnectionBanner()),
      facade: f,
    );
    expect(find.text(S.offline), findsOneWidget);
    await tester.tap(find.byKey(const Key('reconnect')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connection-banner')), findsNothing);
  });
}

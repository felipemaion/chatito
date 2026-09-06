import 'package:chatito/platform/files.dart';
import 'package:chatito/platform/platform_info.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/contracts.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/strings.dart';
import 'package:chatito/ui/widgets/connection_banner.dart';
import 'package:flutter/material.dart';
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

  testWidgets('ConnectionBanner aparece offline/conectando e some online', (
    tester,
  ) async {
    final f = FakeChatFacade.seeded();
    await pumpScreen(
      tester,
      const Scaffold(body: ConnectionBanner()),
      facade: f,
    );
    expect(find.byKey(const Key('connection-banner')), findsNothing);
    f.setConnection(RelayState.offline);
    await tester.pumpAndSettle();
    expect(find.text(S.offline), findsOneWidget);
    f.setConnection(RelayState.connecting);
    await tester.pumpAndSettle();
    expect(find.text(S.connecting), findsOneWidget);
    f.setConnection(RelayState.online);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connection-banner')), findsNothing);
  });

  testWidgets('conversa mostra faixa de offline', (tester) async {
    final f = FakeChatFacade.seeded()..setConnection(RelayState.offline);
    await pumpApp(tester, facade: f, size: phoneSize);
    expect(find.byKey(const Key('connection-banner')), findsOneWidget);
  });
}

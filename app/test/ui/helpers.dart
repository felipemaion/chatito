import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/ui/app.dart';
import 'package:chatito/ui/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const wideSize = Size(1200, 800);
const phoneSize = Size(400, 800);

/// Sobe o app inteiro com a fachada fake e a janela do tamanho pedido.
Future<FakeChatFacade> pumpApp(
  WidgetTester tester, {
  FakeChatFacade? facade,
  Size size = wideSize,
  String? initialLocation,
  List<Override> overrides = const [],
}) async {
  final f = facade ?? FakeChatFacade(autoReplyDelay: Duration.zero);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatFacadeProvider.overrideWithValue(f), ...overrides],
      child: ChatitoApp(initialLocation: initialLocation),
    ),
  );
  await tester.pumpAndSettle();
  return f;
}

/// Sobe só um widget dentro de MaterialApp + ProviderScope (para testes de tela isolada).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  ChatFacade? facade,
  Size size = phoneSize,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatFacadeProvider.overrideWithValue(
          facade ?? FakeChatFacade(autoReplyDelay: Duration.zero),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: ChatitoApp.localizationsDelegates,
        supportedLocales: ChatitoApp.supportedLocales,
        locale: const Locale('pt', 'BR'),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

import 'package:chatito/domain/domain.dart';
import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/app_services.dart';
import 'package:chatito/platform/connectivity.dart';
import 'package:chatito/platform/notifications.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/app.dart';
import 'package:chatito/ui/providers.dart';
import 'package:chatito/ui/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Facade cujo `connect()` falha com `not_registered` quando [shouldFail] é
/// verdadeiro — simula um token sumido/expirado no keychain apesar da sessão
/// em memória continuar "registrada" (bug de campo: token inválido).
class _FailingConnectFacade extends FakeChatFacade {
  _FailingConnectFacade({super.autoReplyDelay});

  /// Começa `false` para o registro inicial (automático, ao montar) não
  /// disparar a falha antes do cenário do teste começar.
  bool shouldFail = false;

  @override
  Future<void> connect() async {
    if (shouldFail) {
      throw const ChatException('not_registered', 'sem token');
    }
    return super.connect();
  }
}

class _NoopNotifier implements LocalNotifications {
  @override
  Future<void> init({required void Function(String payload) onSelect}) async {}
  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {}
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  FakeChatFacade f,
) async {
  final container = ProviderContainer(
    overrides: [
      chatFacadeProvider.overrideWithValue(f),
      pushWakerProvider.overrideWithValue(const NoopPushWaker()),
      connectivityWatcherProvider.overrideWithValue(
        const NoopConnectivityWatcher(),
      ),
      localNotificationsProvider.overrideWithValue(_NoopNotifier()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const AppServices(child: ChatitoApp()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'sessão fica inválida em segundo plano: ao voltar, manda para onboarding com mensagem clara',
    (tester) async {
      final f = _FailingConnectFacade(autoReplyDelay: Duration.zero);
      final container = await _pumpApp(tester, f);
      expect(find.byKey(const Key('conversations')), findsOneWidget);
      expect(container.read(sessionInvalidProvider), isFalse);

      // Simula o token expirando/sumindo enquanto o app estava em segundo plano.
      f.shouldFail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding')), findsOneWidget);
      expect(find.byKey(const Key('session-invalid')), findsOneWidget);
      expect(find.text(S.sessionExpired), findsOneWidget);
      expect(find.text(S.connecting), findsNothing);
      expect(container.read(sessionInvalidProvider), isTrue);
    },
  );

  testWidgets('registrar de novo limpa a mensagem de sessão inválida', (
    tester,
  ) async {
    final f = _FailingConnectFacade(autoReplyDelay: Duration.zero);
    final container = await _pumpApp(tester, f);
    container.read(sessionInvalidProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-invalid')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invite')), '7K3M-9QZR');
    await tester.enterText(find.byKey(const Key('device-name')), 'Novo device');
    await tester.tap(find.byKey(const Key('register')));
    await tester.pumpAndSettle();

    expect(container.read(sessionInvalidProvider), isFalse);
    expect(find.byKey(const Key('conversations')), findsOneWidget);
  });
}

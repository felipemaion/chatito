import 'package:piriquito/domain/domain.dart' show ConnectionState;
import 'package:piriquito/domain/fakes/fake_chat_facade.dart';
import 'package:piriquito/platform/app_services.dart';
import 'package:piriquito/platform/connectivity.dart';
import 'package:piriquito/platform/notifications.dart';
import 'package:piriquito/platform/push.dart';
import 'package:piriquito/ui/providers.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePush implements PushWaker {
  void Function()? wake;
  void Function(String?)? token;
  @override
  Future<void> init({
    required void Function() onWake,
    required void Function(String? token) onToken,
  }) async {
    wake = onWake;
    token = onToken;
  }
}

class _FakeConnectivity implements ConnectivityWatcher {
  void Function()? online;
  @override
  Future<void> init({required void Function() onOnline}) async =>
      online = onOnline;
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

FakeChatFacade _seeded() => FakeChatFacade(autoReplyDelay: Duration.zero);

void main() {
  testWidgets('wake do push conecta a fachada', (tester) async {
    final f = _seeded();
    final push = _FakePush();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(f),
          pushWakerProvider.overrideWithValue(push),
          connectivityWatcherProvider.overrideWithValue(
            const NoopConnectivityWatcher(),
          ),
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const AppServices(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(push.wake, isNotNull);
    push.wake!();
    push.token!('fcm-abc');
    await tester.pump();
    expect(await f.watchConnection().first, ConnectionState.online);
    expect(f.pushToken, 'fcm-abc');
  });

  testWidgets('token FCM recebido antes do registro é enviado ao registrar', (
    tester,
  ) async {
    final f = FakeChatFacade(
      startRegistered: false,
      autoReplyDelay: Duration.zero,
    );
    final push = _FakePush();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(f),
          pushWakerProvider.overrideWithValue(push),
          connectivityWatcherProvider.overrideWithValue(
            const NoopConnectivityWatcher(),
          ),
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const AppServices(child: SizedBox()),
      ),
    );
    await tester.pump();
    push.token!('fcm-cedo');
    await tester.pump();
    expect(f.pushToken, isNull, reason: 'sem sessão não há como enviar');
    await f.register(
      inviteCode: 'ABCD-EFGH',
      deviceName: 'Teste',
      platform: 'android',
    );
    await tester.pump();
    await tester.pump();
    expect(f.pushToken, 'fcm-cedo');
  });

  testWidgets('token FCM atualizado (refresh) é reenviado', (tester) async {
    final f = _seeded();
    final push = _FakePush();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(f),
          pushWakerProvider.overrideWithValue(push),
          connectivityWatcherProvider.overrideWithValue(
            const NoopConnectivityWatcher(),
          ),
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const AppServices(child: SizedBox()),
      ),
    );
    await tester.pump();
    push.token!('fcm-1');
    await tester.pump();
    push.token!('fcm-2');
    await tester.pump();
    expect(f.pushToken, 'fcm-2');
    expect(f.pushTokenCalls, 2);
  });

  testWidgets(
    'registro já existente conecta ao montar; voltar ao primeiro plano reconecta',
    (tester) async {
      final f = _seeded();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatFacadeProvider.overrideWithValue(f),
            pushWakerProvider.overrideWithValue(_FakePush()),
            connectivityWatcherProvider.overrideWithValue(
              const NoopConnectivityWatcher(),
            ),
            localNotificationsProvider.overrideWithValue(_NoopNotifier()),
          ],
          child: const AppServices(child: SizedBox()),
        ),
      );
      await tester.pump();
      expect(await f.watchConnection().first, ConnectionState.online);
      await f.disconnect();
      expect(await f.watchConnection().first, ConnectionState.offline);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await f.watchConnection().first, ConnectionState.online);
    },
  );

  testWidgets('rede voltando reconecta mesmo sem o app ser pausado/retomado', (
    tester,
  ) async {
    final f = _seeded();
    final connectivity = _FakeConnectivity();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(f),
          pushWakerProvider.overrideWithValue(_FakePush()),
          connectivityWatcherProvider.overrideWithValue(connectivity),
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const AppServices(child: SizedBox()),
      ),
    );
    await tester.pump();
    await f.disconnect();
    expect(await f.watchConnection().first, ConnectionState.offline);
    expect(connectivity.online, isNotNull);
    connectivity.online!();
    await tester.pump();
    expect(await f.watchConnection().first, ConnectionState.online);
  });

  test('NoopPushWaker não faz nada', () async {
    await const NoopPushWaker().init(onWake: () {}, onToken: (_) {});
  });

  test('NoopConnectivityWatcher não faz nada', () async {
    await const NoopConnectivityWatcher().init(onOnline: () {});
  });
}

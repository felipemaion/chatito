import 'package:chatito/domain/domain.dart' show ConnectionState;
import 'package:chatito/domain/fakes/fake_chat_facade.dart';
import 'package:chatito/platform/app_services.dart';
import 'package:chatito/platform/notifications.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/providers.dart';
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
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const AppServices(child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(push.wake, isNotNull);
    push.wake!();
    push.token!('fcm-abc'); // sem equivalente na fachada; só não deve lançar
    await tester.pump();
    expect(await f.watchConnection().first, ConnectionState.online);
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

  test('NoopPushWaker não faz nada', () async {
    await const NoopPushWaker().init(onWake: () {}, onToken: (_) {});
  });
}

import 'package:chatito/platform/app_services.dart';
import 'package:chatito/platform/notifications.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/providers.dart';
import 'package:flutter/material.dart';
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

void main() {
  testWidgets('wake do push dispara sync e token vai para a fachada', (
    tester,
  ) async {
    final f = FakeChatFacade.seeded();
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
    push.token!('fcm-abc');
    await tester.pump();
    expect(f.syncCalls, 1);
    expect(f.pushToken, 'fcm-abc');
  });

  testWidgets('voltar ao primeiro plano sincroniza', (tester) async {
    final f = FakeChatFacade.seeded();
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(f.syncCalls, 1);
  });

  test('NoopPushWaker não faz nada', () async {
    await const NoopPushWaker().init(onWake: () {}, onToken: (_) {});
  });
}

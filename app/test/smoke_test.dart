import 'package:chatito/main.dart';
import 'package:chatito/platform/notifications.dart';
import 'package:chatito/platform/push.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(FakeChatFacade.seeded()),
          pushWakerProvider.overrideWithValue(const NoopPushWaker()),
          localNotificationsProvider.overrideWithValue(_NoopNotifier()),
        ],
        child: const MainApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MainApp), findsOneWidget);
  });
}

import 'package:chatito/main.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatFacadeProvider.overrideWithValue(FakeChatFacade.seeded()),
        ],
        child: const MainApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MainApp), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:chatito/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const MainApp());
    expect(find.byType(MainApp), findsOneWidget);
  });
}

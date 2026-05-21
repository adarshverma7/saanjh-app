import 'package:flutter_test/flutter_test.dart';

import 'package:saanjh/app.dart';

void main() {
  testWidgets('App boots to splash', (WidgetTester tester) async {
    await tester.pumpWidget(const SaanjhApp());
    await tester.pump();
    expect(find.text('Saanjh'), findsOneWidget);
  });
}

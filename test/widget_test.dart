import 'package:flutter_test/flutter_test.dart';
import 'package:speech_translator/main.dart';

void main() {
  testWidgets('SpeechTranslator app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Speech Translator'), findsOneWidget);
  });
}

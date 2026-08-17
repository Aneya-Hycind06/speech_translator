import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:speech_translator/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub every plugin channel the screen touches on startup.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async => const {
        'initialize',
        'has_permission',
        'listen',
        'stop',
        'cancel',
      }.contains(call.method),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => null,
    );
  });

  testWidgets('language bar renders, swaps and highlights', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
    // Active side label.
    expect(find.text('SPEAKING'), findsOneWidget);
    expect(find.text('TRANSLATE TO'), findsOneWidget);

    // Swap animation runs and the values exchange places.
    final topBefore = tester.getCenter(find.text('Hindi')).dx;
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final topAfter = tester.getCenter(find.text('Hindi')).dx;
    expect(topAfter, greaterThan(topBefore));

    // Open the left dropdown and pick a language.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamil').last);
    await tester.pumpAndSettle();
    expect(find.text('Tamil'), findsOneWidget);
    expect(find.text('English'), findsNothing);
  });

  testWidgets('holding the mic shows the ripple, timer and waveform',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Two mics on screen at rest: the empty-state glyph and the button.
    expect(find.byIcon(Icons.mic_none_rounded), findsNWidgets(2));
    expect(find.text('LISTENING'), findsNothing);

    final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded).last));
    await tester.pump(const Duration(milliseconds: 700)); // long-press fires
    await tester.pump(const Duration(milliseconds: 300));

    // The button icon plus the "SPEAKING" marker on the active language card.
    expect(find.byIcon(Icons.mic_rounded), findsNWidgets(2));
    expect(find.text('LISTENING'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('RELEASE TO TRANSLATE'), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // Animations must stop with the recording, otherwise pumpAndSettle hangs.
    expect(find.text('LISTENING'), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsNWidgets(2));

    // Let the plugin's internal stop timer drain before the tree is disposed.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('empty state explains what to do', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Hold the microphone'), findsOneWidget);
    expect(find.text('to start translating'), findsOneWidget);
    expect(find.text('Hindi  ⇄  English'), findsOneWidget);
  });

  testWidgets('new chat button sits left of settings and clears the chat',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final refresh = find.byIcon(Icons.refresh_rounded);
    expect(refresh, findsOneWidget);
    expect(tester.getCenter(refresh).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.settings_rounded)).dx));

    // Nothing to clear yet.
    await tester.tap(refresh);
    await tester.pump();
    expect(find.text('Already a new chat'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('quick translate cards render', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick translate'));
    await tester.pumpAndSettle();

    expect(find.text('SOURCE · HINDI'), findsOneWidget);
    expect(find.text('TRANSLATION · ENGLISH'), findsOneWidget);
    expect(find.text('Hold the mic to speak…'), findsOneWidget);
    expect(find.text('The translation will appear here…'), findsOneWidget);
  });
}

import 'package:ayra/main.dart';
import 'package:ayra/widgets/globe_3d.dart';
import 'package:ayra/widgets/orb_3d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ayra home shows the orb and the greeting',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AyraApp());
    await tester.pump();

    expect(find.text('AYRA'), findsOneWidget);
    expect(find.text('Tap to speak'), findsOneWidget);
    expect(
      find.text('Command likho… jaise "12 + 8 calculate karo"'),
      findsOneWidget,
    );
  });

  testWidgets('Typing a command shows Ayra\'s reply',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AyraApp());
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      'calculate 15 * 4',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    // No pumpAndSettle: the 3D globe's animation repeats forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('60'), findsWidgets);
  });

  testWidgets('3D hero (globe + orb) renders without errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Globe3D(size: 120),
              Orb3D(listening: false, onTap: _noop),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Globe3D), findsOneWidget);
    expect(find.byType(Orb3D), findsOneWidget);
    expect(find.text('Tap to speak'), findsOneWidget);
  });
}

void _noop() {}

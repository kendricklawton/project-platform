import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Update this import to match your package name
import 'package:project_dupes/main.dart';

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    // 1. Build the ProjectDupesApp (instead of MyApp) and trigger a frame.
    await tester.pumpWidget(const ProjectDupesApp());

    // 2. Verify that the Dashboard AppBar title is present.
    expect(find.text('Dashboard'), findsOneWidget);

    // 3. Verify that the "Sign In with SSO" button is present.
    //    (Matches the text we added in HomeScreen)
    expect(find.text('Sign In with SSO'), findsOneWidget);

    // 4. Verify that default counter artifacts are GONE.
    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
  });
}

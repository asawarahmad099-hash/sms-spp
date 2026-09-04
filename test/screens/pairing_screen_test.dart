import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sms_gateway/screens/pairing_screen.dart';
import 'package:sms_gateway/state/gateway_state.dart';

void main() {
  Widget wrap(Widget child) {
    return ChangeNotifierProvider(
      create: (_) => GatewayState(),
      child: MaterialApp(home: child),
    );
  }

  testWidgets('shows all four pairing fields and the submit button', (tester) async {
    await tester.pumpWidget(wrap(const PairingScreen()));

    expect(find.widgetWithText(TextFormField, 'API base URL'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Device ID'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Public key'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Secret'), findsOneWidget);
    expect(find.text('Test connection & pair'), findsOneWidget);
  });

  testWidgets('shows a validation error for each required field left empty', (tester) async {
    await tester.pumpWidget(wrap(const PairingScreen()));

    // Clear the pre-filled "https://" default so the URL field is also empty.
    await tester.enterText(find.widgetWithText(TextFormField, 'API base URL'), '');
    await tester.tap(find.text('Test connection & pair'));
    await tester.pump();

    expect(find.text('Enter a valid URL'), findsOneWidget);
    expect(find.text('Required'), findsNWidgets(3)); // Device ID, Public key, Secret
  });

  testWidgets('does not show validation errors once all fields are filled', (tester) async {
    await tester.pumpWidget(wrap(const PairingScreen()));

    await tester.enterText(find.widgetWithText(TextFormField, 'API base URL'), 'https://sms.example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Device ID'), 'device-1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Public key'), 'dev_abc');
    await tester.enterText(find.widgetWithText(TextFormField, 'Secret'), 'shh');

    // Don't tap submit here — that would fire a real network call via the
    // screen's own ApiClient. Validating the form directly exercises the
    // same validator logic without needing to mock HTTP inside the widget.
    final formState = tester.state<FormState>(find.byType(Form));
    expect(formState.validate(), isTrue);
  });
}

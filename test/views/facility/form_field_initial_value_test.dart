import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormField initialValue compliance tests (#405)', () {
    testWidgets(
        'DropdownButtonFormField initializes correctly with initialValue without deprecated value parameter',
        (WidgetTester tester) async {
      String? selectedValue = 'Option A';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return DropdownButtonFormField<String>(
                  initialValue: selectedValue,
                  items: const [
                    DropdownMenuItem(value: 'Option A', child: Text('Option A')),
                    DropdownMenuItem(value: 'Option B', child: Text('Option B')),
                  ],
                  onChanged: (val) {
                    setState(() {
                      selectedValue = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Verify default value is populated correctly
      expect(find.text('Option A'), findsOneWidget);

      // Change selection
      await tester.tap(find.text('Option A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Option B').last);
      await tester.pumpAndSettle();

      expect(selectedValue, equals('Option B'));
    });

    testWidgets('TextFormField initializes correctly with initialValue',
        (WidgetTester tester) async {
      String enteredText = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              initialValue: 'Default Quantity',
              onChanged: (val) => enteredText = val,
            ),
          ),
        ),
      );

      // Verify default initial value displays correctly
      expect(find.text('Default Quantity'), findsOneWidget);

      // Enter new text
      await tester.enterText(find.byType(TextFormField), '100');
      expect(enteredText, equals('100'));
    });
  });
}

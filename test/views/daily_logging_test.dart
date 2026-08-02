import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/views/facility/daily_logging_page.dart';

void main() {
  group('Daily Logging - Vision Image Parsing Tests', () {
    test('parseVisionJson parses plain JSON array string correctly', () {
      const rawText =
          '[{"medicine": "Paracetamol", "quantity": 100, "patients": 25}, {"medicine": "ORS", "quantity": 50, "patients": 10}]';
      final items = parseVisionJson(rawText);

      expect(items.length, 2);
      expect(items[0]['medicine'], 'Paracetamol');
      expect(items[0]['quantity'], 100);
      expect(items[0]['patients'], 25);

      expect(items[1]['medicine'], 'ORS');
      expect(items[1]['quantity'], 50);
      expect(items[1]['patients'], 10);
    });

    test('parseVisionJson handles Markdown code blocks', () {
      const rawText = '''
```json
[
  {"medicine": "Antibiotic", "quantity": 30, "patients": 12}
]
```
''';
      final items = parseVisionJson(rawText);

      expect(items.length, 1);
      expect(items[0]['medicine'], 'Antibiotic');
      expect(items[0]['quantity'], 30);
      expect(items[0]['patients'], 12);
    });

    test('parseVisionJson extracts JSON embedded within extra text', () {
      const rawText = '''
Here is the extracted data from the medicine log sheet:
[{"medicine": "Cough Syrup", "quantity": "15", "patients": "5"}]
Hope this helps!
''';
      final items = parseVisionJson(rawText);

      expect(items.length, 1);
      expect(items[0]['medicine'], 'Cough Syrup');
      expect(items[0]['quantity'], 15);
      expect(items[0]['patients'], 5);
    });

    test('parseVisionJson handles decimal numeric values from vision models',
        () {
      const rawText =
          '[{"medicine": "Paracetamol", "quantity": 100.0, "patients": "25.0"}, {"medicine": "ORS", "quantity": "50.5", "patients": 10.2}]';
      final items = parseVisionJson(rawText);

      expect(items.length, 2);
      expect(items[0]['medicine'], 'Paracetamol');
      expect(items[0]['quantity'], 100);
      expect(items[0]['patients'], 25);

      expect(items[1]['medicine'], 'ORS');
      expect(items[1]['quantity'], 51); // 50.5 rounded to 51
      expect(items[1]['patients'], 10);
    });

    test('parseVisionJson returns empty list for invalid JSON or no array', () {
      expect(parseVisionJson('No JSON data here'), isEmpty);
      expect(parseVisionJson('{"medicine": "Paracetamol"}'), isEmpty);
      expect(parseVisionJson(''), isEmpty);
    });
  });
}

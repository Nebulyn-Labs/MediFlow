import 'package:flutter_test/flutter_test.dart';
import 'package:csv/csv.dart';
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

  group('Daily Logging - CSV Import Parsing Tests', () {
    test('parseCsvContent parses valid rows correctly with header', () {
      final rows = [
        ['MedicineName', 'UnitsDistributed', 'PatientsServed'],
        ['Paracetamol', '100', '25'],
        ['ORS', '50', '10'],
      ];

      final result = parseCsvContent(rows);

      expect(result.items.length, 2);
      expect(result.skippedRows, isEmpty);
      expect(result.items[0]['medicine'], 'Paracetamol');
      expect(result.items[0]['quantity'], 100);
      expect(result.items[0]['patients'], 25);

      expect(result.items[1]['medicine'], 'ORS');
      expect(result.items[1]['quantity'], 50);
      expect(result.items[1]['patients'], 10);
    });

    test('parseCsvContent reports skipped rows with line numbers and reasons',
        () {
      final rows = [
        ['MedicineName', 'UnitsDistributed', 'PatientsServed'],
        ['Paracetamol', '100', '25'], // line 2 (valid)
        ['', '15', '5'], // line 3 (missing medicine name)
        ['Aspirin', 'invalid_qty', '10'], // line 4 (quantity is not a number)
        ['ORS', '0', '0'], // line 5 (quantity must be greater than 0)
        ['Amoxicillin', '30', '12'], // line 6 (valid)
      ];

      final result = parseCsvContent(rows);

      expect(result.items.length, 2);
      expect(result.skippedRows.length, 3);

      expect(result.skippedRows[0].line, 3);
      expect(result.skippedRows[0].reason, 'missing medicine name');

      expect(result.skippedRows[1].line, 4);
      expect(result.skippedRows[1].reason, 'quantity is not a number');

      expect(result.skippedRows[2].line, 5);
      expect(result.skippedRows[2].reason, 'quantity must be greater than 0');
    });

    test('parseCsvContent handles file where every row is skipped', () {
      final rows = [
        ['MedicineName', 'UnitsDistributed', 'PatientsServed'],
        ['', '100', '25'], // line 2
        ['Aspirin', 'not_a_number', '10'], // line 3
      ];

      final result = parseCsvContent(rows);

      expect(result.items, isEmpty);
      expect(result.skippedRows.length, 2);
      expect(result.skippedRows[0].line, 2);
      expect(result.skippedRows[1].line, 3);
    });

    test(
        'parseCsvContent with raw CSV string decoder preserves line numbers with blank lines',
        () {
      const rawCsv = '''MedicineName,UnitsDistributed,PatientsServed
Paracetamol,100,25

Aspirin,not_a_number,10''';

      final rows = const CsvDecoder(skipEmptyLines: false).convert(rawCsv);
      final result = parseCsvContent(rows);

      expect(result.items.length, 1);
      expect(result.items[0]['medicine'], 'Paracetamol');

      expect(result.skippedRows.length, 2);
      // Line 3 is the blank line
      expect(result.skippedRows[0].line, 3);
      expect(result.skippedRows[0].reason, 'empty row');

      // Line 4 is Aspirin with invalid quantity (must not drift to line 3!)
      expect(result.skippedRows[1].line, 4);
      expect(result.skippedRows[1].reason, 'quantity is not a number');
    });
  });
}

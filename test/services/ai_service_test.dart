import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/ai_service.dart';

void main() {
  group('AIService fallback', () {
    test('forecastDemand falls back to local prediction when Gemini throws', () async {
      final service = AIService(
        null,
        geminiCaller: (
          String prompt, {
          String? imageBase64,
          String? imageMimeType,
        }) async {
          throw Exception('quota exceeded');
        },
      );

      final result = await service.forecastDemand(
        'Paracetamol',
        [],
        7,
      );

      expect(result.containsKey('prediction'), isTrue);
      expect(result.containsKey('reasoning'), isTrue);
    });

    test('forecastDemand uses Gemini when available', () async {
      final service = AIService(
        null,
        geminiCaller: (
          String prompt, {
          String? imageBase64,
          String? imageMimeType,
        }) async {
          return '{"prediction":123,"reasoning":"AI result"}';
        },
      );

      final result = await service.forecastDemand(
        'Paracetamol',
        [],
        7,
      );

      expect(result['prediction'], 123);
      expect(result['reasoning'], 'AI result');
    });
  });
}
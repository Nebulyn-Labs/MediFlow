import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/services/ai_service.dart';

void main() {
  group('AI service image MIME detection', () {
    test('infers JPEG and PNG MIME types from file signatures', () {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x01]);
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final aiService = container.read(aiServiceProvider);

      expect(aiService.inferImageMimeType(jpegBytes), 'image/jpeg');
      expect(aiService.inferImageMimeType(pngBytes), 'image/png');
    });

    test('uses picked file extension to derive supported image MIME types', () {
      final imageBytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x00,
        0x00,
        0x00,
        0x00,
        0x57,
        0x45,
        0x42,
        0x50,
      ]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final aiService = container.read(aiServiceProvider);

      expect(
        aiService.imageMimeTypeForPickedFile(
          imageBytes: imageBytes,
          fileName: 'usage-log.webp',
          extension: 'webp',
        ),
        'image/webp',
      );
    });

    test('rejects unsupported picked image types by name', () {
      final gifBytes = Uint8List.fromList([0x47, 0x49, 0x46, 0x38]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final aiService = container.read(aiServiceProvider);

      expect(
        () => aiService.imageMimeTypeForPickedFile(
          imageBytes: gifBytes,
          fileName: 'usage-log.gif',
          extension: 'gif',
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('gif'),
          ),
        ),
      );
    });
  });

  group('AIService fallback', () {
    test('forecastDemand falls back to local prediction when Gemini throws',
        () async {
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

  group('AIService extractJsonPayload & sanitizePromptInput (#422)', () {
    test('extracts JSON payload from markdown fences with json tag', () {
      const input = '```json\n{"prediction": 42, "reasoning": "Test"}\n```';
      final jsonStr = AIService.extractJsonPayload(input);
      expect(jsonStr, '{"prediction": 42, "reasoning": "Test"}');
    });

    test('extracts JSON payload when surrounded by conversational text', () {
      const input = 'Here is the forecast:\n{"prediction": 50, "reasoning": "Ok"}\nHope this helps!';
      final jsonStr = AIService.extractJsonPayload(input);
      expect(jsonStr, '{"prediction": 50, "reasoning": "Ok"}');
    });

    test('sanitizes newline and quote characters in prompt input', () {
      const input = 'Paracetamol\n"500mg"';
      final sanitized = AIService.sanitizePromptInput(input);
      expect(sanitized, r'Paracetamol \"500mg\"');
    });
  });
}

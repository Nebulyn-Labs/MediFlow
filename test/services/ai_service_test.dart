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

  group('AIService shared fallback handling', () {
    AIService serviceWith(GeminiCaller caller) => AIService(
          null,
          geminiCaller: caller,
        );

    test('quota errors latch local mode and skip the remote call', () async {
      var remoteCalls = 0;
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async {
        remoteCalls++;
        throw Exception('quota exceeded');
      });

      expect(service.isLocalFallbackActive, isFalse);

      await service.forecastDemand('Paracetamol', [], 7);
      expect(remoteCalls, 1);
      expect(service.isLocalFallbackActive, isTrue);

      final second = await service.forecastDemand('Paracetamol', [], 7);
      expect(
        remoteCalls,
        1,
        reason: 'remote must be skipped while the quota window is open',
      );
      expect(second.containsKey('prediction'), isTrue);
    });

    test('transient errors fall back without disabling the AI path', () async {
      var remoteCalls = 0;
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async {
        remoteCalls++;
        throw Exception('socket closed');
      });

      await service.forecastDemand('Paracetamol', [], 7);
      expect(service.isLocalFallbackActive, isFalse);

      await service.forecastDemand('Paracetamol', [], 7);
      expect(
        remoteCalls,
        2,
        reason: 'a non-quota failure must not latch local mode',
      );
    });

    test('malformed AI payloads fall back to the local result', () async {
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async =>
          'not json at all');

      final result = await service.forecastDemand('ORS', [], 7);

      expect(result['prediction'], isA<int>());
      expect(result['reasoning'], contains('Seasonal logic'));
      expect(service.isLocalFallbackActive, isFalse);
    });

    test('markdown code fences around AI JSON are stripped', () async {
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async =>
          '```json\n{"prediction":42,"reasoning":"fenced"}\n```');

      final result = await service.forecastDemand('ORS', [], 7);

      expect(result['prediction'], 42);
      expect(result['reasoning'], 'fenced');
    });

    test('workflows without a quota pre-check still reach Gemini', () async {
      var shipmentCalls = 0;
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async {
        if (prompt.startsWith('Forecast')) {
          throw Exception('quota exceeded');
        }
        shipmentCalls++;
        return '{"Paracetamol":{"active":10,"coldStorage":5,"reasoning":"AI"}}';
      });

      await service.forecastDemand('Paracetamol', [], 7);
      expect(service.isLocalFallbackActive, isTrue);

      final plan = await service.suggestShipmentAllocation(items: [], logs: []);

      expect(
        shipmentCalls,
        1,
        reason: 'suggestShipmentAllocation deliberately ignores the quota flag',
      );
      expect(plan['Paracetamol'], isNotNull);
    });

    test('empty wastage data returns local advice without calling Gemini',
        () async {
      var remoteCalls = 0;
      final service = serviceWith((
        String prompt, {
        String? imageBase64,
        String? imageMimeType,
      }) async {
        remoteCalls++;
        return 'unused';
      });

      final advice = await service.getWastageRecommendations([]);

      expect(remoteCalls, 0);
      expect(advice, contains('Local analysis suggests'));
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_supply_prototype/models/facility.dart';
import 'package:med_supply_prototype/models/request.dart';
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

  group('generateRedistributionPlan', () {
    final facility1 = Facility(
      id: 'fac1',
      name: 'Rampur PHC',
      email: 'rampur@phc.com',
      type: 'rural',
      region: 'North',
      latitude: 28.5,
      longitude: 77.1,
      createdAt: DateTime.now(),
    );

    final pendingRegularIndent = MedRequest(
      id: 'req1',
      facilityId: 'fac1',
      medicineName: 'ORS',
      type: RequestType.regularIndent,
      quantity: 500,
      requestDate: DateTime.now(),
      status: RequestStatus.pending,
    );

    final approvedShortageIndent = MedRequest(
      id: 'req2',
      facilityId: 'fac1',
      medicineName: 'Amoxicillin',
      type: RequestType.shortage,
      quantity: 300,
      requestDate: DateTime.now(),
      status: RequestStatus.approved,
    );

    final fulfilledIndent = MedRequest(
      id: 'req3',
      facilityId: 'fac1',
      medicineName: 'Paracetamol',
      type: RequestType.regularIndent,
      quantity: 100,
      requestDate: DateTime.now(),
      status: RequestStatus.fulfilled,
    );

    final surplusRequest = MedRequest(
      id: 'req4',
      facilityId: 'fac1',
      medicineName: 'ORS',
      type: RequestType.surplus,
      quantity: 200,
      requestDate: DateTime.now(),
      status: RequestStatus.pending,
    );

    test('returns default message when no eligible indents exist', () async {
      final service = AIService(null);
      final result = await service.generateRedistributionPlan(
        [fulfilledIndent, surplusRequest],
        [facility1],
      );
      expect(result, 'No active indents found to optimize.');
    });

    test('filters pending/approved regularIndent and shortage requests and calls Gemini',
        () async {
      String? capturedPrompt;
      final service = AIService(
        null,
        geminiCaller: (
          String prompt, {
          String? imageBase64,
          String? imageMimeType,
        }) async {
          capturedPrompt = prompt;
          return 'Prioritized Rampur PHC for ORS and Amoxicillin redistribution.';
        },
      );

      final result = await service.generateRedistributionPlan(
        [
          pendingRegularIndent,
          approvedShortageIndent,
          fulfilledIndent,
          surplusRequest,
        ],
        [facility1],
      );

      expect(capturedPrompt, contains('Analyze these 2 pending indents'));
      expect(capturedPrompt, contains('ORS (500 units)'));
      expect(capturedPrompt, contains('Amoxicillin (300 units)'));
      expect(capturedPrompt, isNot(contains('Paracetamol')));
      expect(
        result,
        'Prioritized Rampur PHC for ORS and Amoxicillin redistribution.',
      );
    });

    test('falls back to default summary when Gemini throws an exception',
        () async {
      final service = AIService(
        null,
        geminiCaller: (
          String prompt, {
          String? imageBase64,
          String? imageMimeType,
        }) async {
          throw Exception('network failure');
        },
      );

      final result = await service.generateRedistributionPlan(
        [pendingRegularIndent, approvedShortageIndent],
        [facility1],
      );

      expect(
        result,
        'Optimizing 2 requests across 1 sites by matching local surpluses.',
      );
    });
  });
}


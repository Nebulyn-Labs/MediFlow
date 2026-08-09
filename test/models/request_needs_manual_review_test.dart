import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:med_supply_prototype/models/request.dart';

// -----------------------------------------------------------------------------
// Issue #314: onIndentApproved used to leave a retryable-vs-permanent
// distinction entirely server-side. A non-retryable, non-business-rule
// failure was written to Firestore as status: "approval_failed", a value
// MedRequest.fromMap didn't recognise — so it silently fell back to
// "pending" and the request reappeared in the admin approvals queue with
// no indication anything had gone wrong.
//
// The fix adds RequestStatus.needsManualReview, written by the server as
// the matching "needsManualReview" string, so fromMap decodes it correctly
// instead of masking it as pending.
// -----------------------------------------------------------------------------

MedRequest _request({
  required String id,
  required RequestStatus status,
}) {
  return MedRequest(
    id: id,
    facilityId: 'fac-1',
    medicineName: 'Paracetamol',
    type: RequestType.regularIndent,
    quantity: 10,
    requestDate: DateTime(2026, 1, 1),
    status: status,
  );
}

void main() {
  group('MedRequest.fromMap decodes needsManualReview (#314)', () {
    test('does not fall back to pending for status: "needsManualReview"', () {
      final request = MedRequest.fromMap({
        'facilityId': 'fac-1',
        'medicineName': 'Paracetamol',
        'type': 'regularIndent',
        'quantity': 10,
        'requestDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'status': 'needsManualReview',
        'needsManualReview': true,
      }, 'req-1');

      expect(request.status, RequestStatus.needsManualReview);
      expect(request.status, isNot(RequestStatus.pending));
    });

    test('still falls back to pending for a genuinely unrecognised status',
        () {
      final request = MedRequest.fromMap({
        'facilityId': 'fac-1',
        'medicineName': 'Paracetamol',
        'type': 'regularIndent',
        'quantity': 10,
        'requestDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'status': 'some_future_status_the_client_does_not_know_about',
      }, 'req-2');

      expect(request.status, RequestStatus.pending);
    });
  });

  group('MedRequest.countPending excludes needsManualReview (#314)', () {
    test('a needsManualReview request is not counted as pending', () {
      final all = [
        _request(id: '1', status: RequestStatus.pending),
        _request(id: '2', status: RequestStatus.needsManualReview),
        _request(id: '3', status: RequestStatus.approved),
      ];

      // Before #314 this request would have decoded as "pending" and been
      // double-counted here and in the /admin/approvals list, where a
      // re-attempt at automatic approval processing would silently repeat
      // whatever failed the first time.
      expect(MedRequest.countPending(all), 1);
      expect(MedRequest.filterPending(all).map((r) => r.id), ['1']);
    });
  });

  group('MedRequest.countNeedsManualReview (#314)', () {
    test('counts only needsManualReview requests', () {
      final all = [
        _request(id: '1', status: RequestStatus.pending),
        _request(id: '2', status: RequestStatus.needsManualReview),
        _request(id: '3', status: RequestStatus.needsManualReview),
        _request(id: '4', status: RequestStatus.rejected),
      ];

      expect(MedRequest.countNeedsManualReview(all), 2);
    });

    test('returns 0 when nothing needs review', () {
      final all = [
        _request(id: '1', status: RequestStatus.pending),
        _request(id: '2', status: RequestStatus.approved),
      ];

      expect(MedRequest.countNeedsManualReview(all), 0);
    });
  });

  group('RequestStatusLabel (#314)', () {
    test('needsManualReview reads as "Needs Review", not a raw enum name',
        () {
      expect(RequestStatus.needsManualReview.label, 'Needs Review');
    });

    test('every status has a human-readable label', () {
      for (final status in RequestStatus.values) {
        expect(status.label, isNotEmpty);
        expect(status.label, isNot(contains('_')));
      }
    });
  });
}

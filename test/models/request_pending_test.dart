import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:med_supply_prototype/models/request.dart';

// -----------------------------------------------------------------------------
// Issue #334: the "Pending Indent Approvals" KPI on the admin dashboard
// showed a different number than the /admin/approvals page it linked to.
// The KPI counted only `regularIndent` requests; the page listed every
// pending request regardless of type. The fix moves the "what is pending"
// predicate onto the MedRequest model and uses the same definition in both
// places.
// -----------------------------------------------------------------------------

MedRequest _request({
  required String id,
  required RequestType type,
  required RequestStatus status,
}) {
  return MedRequest(
    id: id,
    facilityId: 'fac-1',
    medicineName: 'M',
    type: type,
    quantity: 1,
    requestDate: DateTime(2026, 1, 1),
    status: status,
  );
}

/// Tests the "what is pending" predicate that #334 introduced. The KPI
/// and /admin/approvals page both go through MedRequest.countPending /
/// MedRequest.filterPending so they cannot drift apart.

void main() {
  group('MedRequest pending helpers (#334)', () {
    test('countPending and filterPending agree on the same set', () {
      final all = [
        _request(
            id: '1',
            type: RequestType.regularIndent,
            status: RequestStatus.pending),
        _request(
            id: '2', type: RequestType.shortage, status: RequestStatus.pending),
        _request(
            id: '3', type: RequestType.surplus, status: RequestStatus.pending),
        _request(
            id: '4',
            type: RequestType.regularIndent,
            status: RequestStatus.approved),
        _request(
            id: '5',
            type: RequestType.shortage,
            status: RequestStatus.rejected),
      ];

      expect(MedRequest.countPending(all), 3);
      expect(MedRequest.filterPending(all).length, 3);
      expect(
        MedRequest.filterPending(all).map((r) => r.id).toList(),
        ['1', '2', '3'],
      );
    });

    test('countPending returns 0 on an empty list', () {
      expect(MedRequest.countPending(const []), 0);
      expect(MedRequest.filterPending(const []), isEmpty);
    });

    test('countPending is type-agnostic — every type counts', () {
      final all = [
        _request(
            id: 'a',
            type: RequestType.regularIndent,
            status: RequestStatus.pending),
        _request(
            id: 'b', type: RequestType.shortage, status: RequestStatus.pending),
        _request(
            id: 'c', type: RequestType.surplus, status: RequestStatus.pending),
      ];
      // Before #334 the KPI only counted regularIndent (a), so the
      // mismatch with /admin/approvals (a + b + c) was 1 vs 3.
      expect(MedRequest.countPending(all), 3);
    });
  });

  group('Dashboard KPI and /admin/approvals agree (#334)', () {
    test('countPending matches the filterPending length for the same data', () {
      // This is the regression test for the issue: the KPI used to count
      // only `regularIndent` requests while the page listed every
      // pending request. With the shared helpers they cannot diverge.
      final all = [
        _request(
            id: '1',
            type: RequestType.regularIndent,
            status: RequestStatus.pending),
        _request(
            id: '2', type: RequestType.shortage, status: RequestStatus.pending),
        _request(
            id: '3', type: RequestType.surplus, status: RequestStatus.pending),
        _request(
            id: '4',
            type: RequestType.regularIndent,
            status: RequestStatus.approved),
        _request(
            id: '5',
            type: RequestType.shortage,
            status: RequestStatus.fulfilled),
      ];

      // The KPI displays MedRequest.countPending(all). The
      // /admin/approvals page renders MedRequest.filterPending(all).
      // They must agree.
      final kpi = MedRequest.countPending(all);
      final rows = MedRequest.filterPending(all).length;
      expect(kpi, rows);
      expect(kpi, 3,
          reason:
              'Before #334 the KPI only counted regularIndent (1) while the '
              'page listed all pending (3). After the fix both report 3.');
    });
  });

  group('Admin dashboard label (#334)', () {
    // The previous label was "PENDING INDENT APPROVALS", which described
    // what the buggy count counted. After the fix the label must read
    // "PENDING APPROVALS" so it matches the page it links to. We check
    // the source file directly so the test does not need a live
    // firebase backend.
    test('admin_overview.dart does not contain the old label', () {
      final source =
          File('lib/views/admin/admin_overview.dart').readAsStringSync();
      expect(source, isNot(contains('PENDING INDENT APPROVALS')),
          reason:
              'The KPI card should use the new label "PENDING APPROVALS" so '
              'it describes what the count actually represents (#334).');
      expect(source, contains("'PENDING APPROVALS'"),
          reason:
              'The KPI card should label itself "PENDING APPROVALS" to match '
              'the /admin/approvals page it links to.');
    });
  });
}

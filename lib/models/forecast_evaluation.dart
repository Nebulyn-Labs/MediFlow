import 'package:cloud_firestore/cloud_firestore.dart';

class ForecastEvaluation {
  final String decisionId;
  final String facilityId;
  final String medicineName;
  final int prediction;
  final int actualUsage;
  final num absoluteError;
  final num mape;
  final num bias;
  final int periodDays;
  final DateTime decisionDate;
  final DateTime evaluatedAt;

  ForecastEvaluation({
    required this.decisionId,
    required this.facilityId,
    required this.medicineName,
    required this.prediction,
    required this.actualUsage,
    required this.absoluteError,
    required this.mape,
    required this.bias,
    required this.periodDays,
    required this.decisionDate,
    required this.evaluatedAt,
  });

  factory ForecastEvaluation.fromMap(Map<String, dynamic> data, String id) {
    return ForecastEvaluation(
      decisionId: id,
      facilityId: data['facilityId'] as String? ?? 'global',
      medicineName: data['medicineName'] as String? ?? 'Unknown',
      prediction: (data['prediction'] as num?)?.toInt() ?? 0,
      actualUsage: (data['actualUsage'] as num?)?.toInt() ?? 0,
      absoluteError: data['absoluteError'] as num? ?? 0,
      mape: data['mape'] as num? ?? 0,
      bias: data['bias'] as num? ?? 0,
      periodDays: (data['periodDays'] as num?)?.toInt() ?? 30,
      decisionDate: data['decisionDate'] is Timestamp
          ? (data['decisionDate'] as Timestamp).toDate()
          : (data['decisionDate'] is String
              ? DateTime.tryParse(data['decisionDate'] as String) ??
                  DateTime.now()
              : DateTime.now()),
      evaluatedAt: data['evaluatedAt'] is Timestamp
          ? (data['evaluatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}

import 'package:intl/intl.dart';

class DateFormatter {
  /// Formats a [DateTime] into a standard app-wide string format (e.g., "07/03/2026").
  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Formats a nullable [DateTime], returning a fallback string if null.
  static String formatNullableDate(DateTime? date, {String fallback = '—'}) {
    if (date == null) return fallback;
    return formatDate(date);
  }
}

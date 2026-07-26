import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

/// Shows a SnackBar with a message and a "Retry" action button.
///
/// Used after a failed Cloud Function or Firestore operation so retry
/// behavior (label, styling, duration) stays consistent across the app
/// instead of each page reimplementing its own error SnackBar.
void showRetrySnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onRetry,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: MediColors.error,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Retry',
        textColor: Colors.white,
        onPressed: onRetry,
      ),
    ),
  );
}

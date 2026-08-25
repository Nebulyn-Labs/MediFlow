import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/main.dart' show profileCache;

/// Shows a confirmation dialog for logging out.
/// Returns true if the user confirms, false otherwise.
Future<bool> confirmLogout(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          // Close the dialog and return false
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          // Close the dialog and return true
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: MediColors.error),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Prompts the user with a confirmation dialog, signs out via [FirebaseAuth],
/// and navigates to the root route upon success. Shows an error snackbar if sign-out fails.
Future<void> signOutWithConfirmation(BuildContext context,
    {FirebaseAuth? auth}) async {
  final confirmed = await confirmLogout(context);
  if (!confirmed) return;
  try {
    await (auth ?? FirebaseAuth.instance).signOut();
    profileCache.clear();
    if (context.mounted) context.go('/');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign out failed: ${e.toString()}'),
          backgroundColor: MediColors.error,
        ),
      );
    }
  }
}

/// Shows a confirmation dialog before running the analytics simulation.
/// Warns that it writes synthetic demo data on top of the facility's
/// real usage history. Returns true if the user confirms, false otherwise.
Future<bool> confirmSimulateAnalytics(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Simulate analytics?'),
      content: const Text(
        'This writes 30 days of synthetic demo usage data and resets '
        'inventory levels for this facility. It will mix with any real '
        'data already logged and cannot be undone. Continue?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: MediColors.error),
          child: const Text('Simulate'),
        ),
      ],
    ),
  );
  return result ?? false;
}

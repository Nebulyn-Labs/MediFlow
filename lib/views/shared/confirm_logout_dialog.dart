import 'package:flutter/material.dart';
import 'package:med_supply_prototype/constants/colors.dart';

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

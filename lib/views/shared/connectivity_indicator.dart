import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:med_supply_prototype/constants/colors.dart';
import 'package:med_supply_prototype/services/connectivity_service.dart';

/// Compact online/offline pill, sized for an [AppBar] action slot.
///
/// The label collapses to an icon on narrow layouts; the tooltip always spells
/// the status out.
class ConnectivityIndicator extends ConsumerWidget {
  const ConnectivityIndicator({super.key});

  /// Below this width only the icon is shown, to keep the app bar from
  /// overflowing on phones.
  static const double _compactWidth = 600;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final color = isOnline ? MediColors.success : MediColors.warning;
    final label = isOnline ? 'Online' : 'Offline';
    final tooltip = isOnline
        ? 'Online — changes are saved in real time'
        : 'Offline — connect to the internet to save changes';
    final showLabel = MediaQuery.sizeOf(context).width >= _compactWidth;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        liveRegion: true,
        label: 'Connectivity status: $label',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                color: color,
                size: 16,
              ),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width notice explaining what is unavailable while the device is
/// offline. Renders nothing when online.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({
    super.key,
    this.message =
        'You are offline. Saving, exporting and AI features are paused and '
            'will resume automatically once you reconnect.',
  });

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: isOnline
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: MediColors.warning.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded,
                      color: MediColors.warning, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: MediColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:med_supply_prototype/theme/medi_flow_theme.dart';
import '../../services/firebase_service.dart';
import '../../models/notification.dart' as notif;
import 'package:intl/intl.dart';

class NotificationFeedWidget extends ConsumerWidget {
  final String facilityId;

  const NotificationFeedWidget({
    super.key,
    required this.facilityId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mediTheme;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notifications',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              color: colors.surface,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.border, width: 1),
              ),
              child: StreamBuilder<List<notif.NotificationModel>>(
                stream: ref
                    .read(firebaseServiceProvider)
                    .streamNotifications(facilityId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error loading notifications.',
                          style: TextStyle(color: colors.error)),
                    );
                  }

                  final notifications = snapshot.data ?? [];

                  if (notifications.isEmpty) {
                    return Center(
                      child: Text('No notifications yet.',
                          style: TextStyle(color: colors.textSecondary)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: colors.border,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, index) {
                      final item = notifications[index];
                      return _NotificationTile(
                        notification: item,
                        colors: colors,
                        onMarkRead: () {
                          if (!item.isRead) {
                            ref
                                .read(firebaseServiceProvider)
                                .markNotificationRead(facilityId, item.id);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final notif.NotificationModel notification;
  final MediFlowTheme colors;
  final VoidCallback onMarkRead;

  const _NotificationTile({
    required this.notification,
    required this.colors,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock = notification.type == 'low_stock';

    return InkWell(
      onTap: onMarkRead,
      child: Container(
        color: notification.isRead
            ? Colors.transparent
            : colors.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLowStock
                    ? colors.error.withValues(alpha: 0.1)
                    : colors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLowStock
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
                color: isLowStock ? colors.error : colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: notification.isRead
                          ? colors.textSecondary
                          : colors.textPrimary,
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMd().add_jm().format(notification.createdAt),
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

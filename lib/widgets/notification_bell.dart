import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../screens/notifications/notification_list_screen.dart';

/// Reusable notification bell with a live unread-count badge.
/// Drop this into any dashboard header (Donor, Recipient, Hospital,
/// Blood Bank, Doctor) — pass in the current uid and the role's primary
/// color so the badge/icon match that dashboard's theme.
class NotificationBell extends StatelessWidget {
  final String uid;
  final Color primaryColor;

  const NotificationBell({
    super.key,
    required this.uid,
    required this.primaryColor,
  });

  Future<void> _openNotifications(BuildContext context) async {
    // NotificationListScreen pops with a String message when the tapped
    // notification has no detail screen yet (request/message types) —
    // we show that message here, using THIS dashboard's own Scaffold
    // context, since the notification screen's own Scaffold is gone by
    // the time it pops.
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationListScreen(uid: uid, primaryColor: primaryColor),
      ),
    );

    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService.unreadCount(uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return GestureDetector(
          onTap: () => _openNotifications(context),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
              ),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
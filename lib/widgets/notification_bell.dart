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

  void _openNotifications(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationListScreen(uid: uid, primaryColor: primaryColor),
      ),
    );
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
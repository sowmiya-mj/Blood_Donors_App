import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../services/notification_service.dart';

class NotificationListScreen extends StatelessWidget {
  final String uid;
  final Color primaryColor;

  const NotificationListScreen({
    super.key,
    required this.uid,
    required this.primaryColor,
  });

  // Icon + color per notification type — keeps the list scannable at a glance.
  (IconData, Color) _styleFor(String type) {
    switch (type) {
      case 'request':
        return (Icons.volunteer_activism_rounded, Colors.red);
      case 'request_accepted':
        return (Icons.check_circle_rounded, Colors.green);
      case 'request_declined':
        return (Icons.cancel_rounded, Colors.grey);
      case 'message':
        return (Icons.chat_bubble_rounded, Colors.blue);
      default:
        return (Icons.notifications_rounded, Colors.orange);
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _onTapNotification(BuildContext context, String notifId, Map<String, dynamic> data) {
    HapticFeedback.lightImpact();
    NotificationService.markAsRead(uid, notifId);

    final type = data['type'] as String? ?? '';
    // NOTE: request/chat detail screens are built in later phases (Phase 3 & 4).
    // For now, tapping just marks read and shows what it would open — this gets
    // wired to real navigation once those screens exist.
    String target = type == 'message' ? 'Chat screen' : 'Request screen';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opens $target (coming in a later phase)'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              NotificationService.markAllAsRead(uid);
            },
            child: const Text('Mark all read', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: NotificationService.notificationsStream(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 50, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No notifications yet',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final (icon, color) = _styleFor(data['type'] as String? ?? '');

              return GestureDetector(
                onTap: () => _onTapNotification(context, doc.id, data),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isRead ? Colors.grey.shade100 : color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['title'] ?? '',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['body'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _timeAgo(data['createdAt'] as Timestamp?),
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
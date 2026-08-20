import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../services/notification_service.dart';
import '../../screens/donor/donor_blood_camps_screen.dart';

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
      case 'new_camp':
        return (Icons.campaign_rounded, Colors.deepPurple);
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

  Future<void> _onTapNotification(
      BuildContext context, String notifId, Map<String, dynamic> data) async {
    HapticFeedback.lightImpact();
    NotificationService.markAsRead(uid, notifId);

    final type = data['type'] as String? ?? '';

    // new_camp -> real navigation. Fetch the donor doc fresh (not cached from
    // whatever screen opened this list) so DonorBloodCampsScreen always gets
    // current data.
    if (type == 'new_camp') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(child: CircularProgressIndicator(color: primaryColor)),
      );

      try {
        final donorDoc =
        await FirebaseFirestore.instance.collection('donors').doc(uid).get();

        if (!context.mounted) return;
        Navigator.pop(context); // close loading dialog

        if (!donorDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not load your profile. Try again.')),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DonorBloodCampsScreen(
              donorData: donorDoc.data(),
              primaryColor: primaryColor,
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        Navigator.pop(context); // close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong opening Blood Camps.')),
        );
      }
      return;
    }

    // request / message / request_accepted / request_declined -> no detail
    // screen exists yet (SOS is an embedded Home-tab widget, chat is still
    // deferred). Pop back to whichever dashboard opened this list and let
    // that screen show a "check your Home tab" snackbar with its own
    // context (see NotificationBell._openNotifications).
    Navigator.pop(context, 'Check your Home tab for the latest updates.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.redAccent,
        foregroundColor: primaryColor,
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
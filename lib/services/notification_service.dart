import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized notification service used by every role (Donor, Recipient,
/// Hospital, Blood Bank, Doctor). Notifications are stored per-user at:
/// notifications/{uid}/items/{notif_id}
class NotificationService {
  static final _db = FirebaseFirestore.instance;

  /// Creates a notification for a specific user.
  /// type: "request" | "message" | "request_accepted" | "request_declined"
  /// relatedId: the request_id or chat_id this notification points to,
  /// used later for tap-to-navigate.
  static Future<void> send({
    required String toUid,
    required String type,
    required String title,
    required String body,
    String? relatedId,
  }) async {
    try {
      await _db
          .collection('notifications')
          .doc(toUid)
          .collection('items')
          .add({
        'type': type,
        'title': title,
        'body': body,
        'related_id': relatedId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Notification failure should never block the main action
      // (e.g. a request being sent). Fail silently.
    }
  }

  /// Live unread count — used for the badge on the notification bell icon.
  static Stream<int> unreadCount(String uid) {
    return _db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Full notification list, most recent first — used by the list screen.
  static Stream<QuerySnapshot> notificationsStream(String uid) {
    return _db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  static Future<void> markAsRead(String uid, String notifId) async {
    await _db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(notifId)
        .update({'read': true});
  }

  /// Marks everything read in one batch — used by a "Mark all read" action.
  static Future<void> markAllAsRead(String uid) async {
    final unread = await _db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}
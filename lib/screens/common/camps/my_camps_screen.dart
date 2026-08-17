import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_edit_camp_screen.dart';

// Shared by Hospital and Blood Bank roles. Pass organizerRole + organizerName
// (+ optional organizerPhone) from whichever dashboard is hosting this.
class MyCampsScreen extends StatefulWidget {
  final Color primaryColor;
  final String organizerRole; // 'hospital' or 'blood_bank'
  final String organizerName;
  final String? organizerPhone;

  const MyCampsScreen({
    super.key,
    required this.primaryColor,
    required this.organizerRole,
    required this.organizerName,
    this.organizerPhone,
  });

  @override
  State<MyCampsScreen> createState() => _MyCampsScreenState();
}

class _MyCampsScreenState extends State<MyCampsScreen> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _cancelCamp(String campId) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this camp?'),
        content: const Text('Registered donors will no longer see this camp. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Yes, cancel', style: TextStyle(color: Colors.red.shade600))),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance.collection('blood_camps').doc(campId).update({'status': 'cancelled'});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camp cancelled')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: const Text('My Blood Camps'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: color,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Camp'),
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateEditCampScreen(
                primaryColor: color,
                organizerRole: widget.organizerRole,
                organizerName: widget.organizerName,
                organizerPhone: widget.organizerPhone,
              ),
            ),
          );
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        // NOTE: equality (organizer_uid) + orderBy(date) needs a composite
        // index. Firestore will throw a failed-precondition error with a
        // direct "create index" console link the first time this runs —
        // just click it once and the index builds itself.
        stream: FirebaseFirestore.instance
            .collection('blood_camps')
            .where('organizer_uid', isEqualTo: _uid)
            .orderBy('date')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: color));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.campaign_outlined, size: 50, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No blood camps yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Tap "New Camp" to organize your first drive',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ]),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final c = doc.data() as Map<String, dynamic>;
              final status = c['status'] ?? 'active';
              final isCancelled = status == 'cancelled';
              final date = (c['date'] as Timestamp?)?.toDate();
              final regCount = c['registered_count'] ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(c['title'] ?? 'Blood Camp',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isCancelled ? Colors.grey.shade400 : const Color(0xFF1A1A2E),
                                decoration: isCancelled ? TextDecoration.lineThrough : null))),
                    if (isCancelled)
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text('Cancelled',
                              style: TextStyle(fontSize: 10, color: Colors.red.shade600, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 6),
                  if (date != null)
                    Row(children: [
                      Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text('${date.day}/${date.month}/${date.year}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      if ((c['start_time'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                            '${c['start_time']}${(c['end_time'] ?? '').toString().isNotEmpty ? ' - ${c['end_time']}' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            [c['city'], c['district'], c['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text('$regCount registered', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
                  if (!isCancelled) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => CreateEditCampScreen(
                                      primaryColor: color,
                                      organizerRole: widget.organizerRole,
                                      organizerName: widget.organizerName,
                                      organizerPhone: widget.organizerPhone,
                                      existingCamp: c,
                                      campId: doc.id,
                                    ))),
                            icon: const Icon(Icons.edit_outlined, size: 15),
                            label: const Text('Edit', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: color,
                                side: BorderSide(color: color.withValues(alpha: 0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _cancelCamp(doc.id),
                            icon: const Icon(Icons.close_rounded, size: 15),
                            label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade600,
                                side: BorderSide(color: Colors.red.shade200),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          )),
                    ]),
                  ],
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
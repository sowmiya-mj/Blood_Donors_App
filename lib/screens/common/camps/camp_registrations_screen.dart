import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'camp_certificate_helper.dart';

// Organizer-facing (Hospital / Blood Bank). Opened by tapping the
// registered-count chip on MyCampsScreen. Shows Confirmed + Waitlisted
// donors, lets the organizer reject a registration (frees the slot and
// auto-promotes the next waitlisted donor), and — once the camp date has
// passed — lets the organizer mark each donor's real outcome
// (Donated / Volunteered / No-show), which is what actually writes a
// verified donation record + issues a certificate.
class CampRegistrationsScreen extends StatefulWidget {
  final String campId;
  final String campTitle;
  final String organizerName;
  final DateTime? campDate;
  final Color primaryColor;

  const CampRegistrationsScreen({
    super.key,
    required this.campId,
    required this.campTitle,
    required this.organizerName,
    required this.campDate,
    required this.primaryColor,
  });

  @override
  State<CampRegistrationsScreen> createState() => _CampRegistrationsScreenState();
}

class _CampRegistrationsScreenState extends State<CampRegistrationsScreen> {
  bool get _isPast => widget.campDate != null && widget.campDate!.isBefore(DateTime.now());

  CollectionReference<Map<String, dynamic>> get _regsRef => FirebaseFirestore.instance
      .collection('blood_camps').doc(widget.campId).collection('registrations');

  // ---------------- Reject ----------------
  Future<void> _reject(QueryDocumentSnapshot<Map<String, dynamic>> reg) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove this donor?'),
        content: Text('${reg.data()['donor_name'] ?? 'This donor'} will be removed from the camp list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove', style: TextStyle(color: Colors.red.shade600))),
        ],
      ),
    );
    if (confirmed != true) return;

    final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(widget.campId);
    final wasConfirmed = reg.data()['reg_status'] == 'confirmed';
    await reg.reference.delete();
    await campRef.update({
      (wasConfirmed ? 'registered_count' : 'waitlist_count'): FieldValue.increment(-1),
    });
    if (wasConfirmed) await _promoteFromWaitlist(campRef);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donor removed')));
    }
  }

  Future<void> _promoteFromWaitlist(DocumentReference campRef) async {
    try {
      final q = await campRef.collection('registrations')
          .where('reg_status', isEqualTo: 'waitlisted')
          .orderBy('registered_at')
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final promoteRef = q.docs.first.reference;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(promoteRef);
        if (!snap.exists || (snap.data() as Map)['reg_status'] != 'waitlisted') return;
        tx.update(promoteRef, {'reg_status': 'confirmed'});
        tx.update(campRef, {
          'registered_count': FieldValue.increment(1),
          'waitlist_count': FieldValue.increment(-1),
        });
      });
    } catch (_) {}
  }

  // ---------------- Outcome marking ----------------
  Future<void> _markOutcome(QueryDocumentSnapshot<Map<String, dynamic>> reg, String outcome) async {
    HapticFeedback.mediumImpact();
    final data = reg.data();
    final donorUid = reg.id;

    await reg.reference.update({'outcome': outcome, 'outcome_marked_at': FieldValue.serverTimestamp()});

    if (outcome == 'donated') {
      await FirebaseFirestore.instance.collection('donors').doc(donorUid).collection('donations').add({
        'type': 'Whole Blood',
        'location': widget.campTitle,
        'date_display': widget.campDate != null ? DateFormat('d MMM yyyy').format(widget.campDate!) : '',
        'units': 1,
        'verified': true,
        'source': 'camp',
        'camp_id': widget.campId,
        'camp_title': widget.campTitle,
        'created_at': FieldValue.serverTimestamp(),
      });
      await reg.reference.update({'certificate_issued': true});
    } else if (outcome == 'volunteered') {
      await FirebaseFirestore.instance.collection('donors').doc(donorUid).collection('camp_participations').add({
        'type': 'volunteer',
        'camp_id': widget.campId,
        'camp_title': widget.campTitle,
        'date': widget.campDate != null ? Timestamp.fromDate(widget.campDate!) : null,
        'organizer_name': widget.organizerName,
        'created_at': FieldValue.serverTimestamp(),
      });
      await reg.reference.update({'certificate_issued': true});
    }

    if (mounted) {
      final label = outcome == 'donated' ? 'Marked as Donated — badge unlocked'
          : outcome == 'volunteered' ? 'Marked as Volunteered'
          : 'Marked as No-show';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(label),
        backgroundColor: outcome == 'no_show' ? Colors.grey.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }

    if (!mounted) return;
    if (outcome == 'donated' || outcome == 'volunteered') {
      await CampCertificateHelper.generateAndShare(
        donorName: (data['donor_name'] ?? 'Donor').toString(),
        campTitle: widget.campTitle,
        organizerName: widget.organizerName,
        date: widget.campDate ?? DateTime.now(),
        type: outcome == 'donated' ? CertificateType.donation : CertificateType.volunteer,
      );
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
        title: Text(widget.campTitle, style: const TextStyle(fontSize: 15)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _regsRef.orderBy('registered_at').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: color));
          }
          if (snap.hasError) {
            return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12))));
          }
          final docs = snap.data?.docs ?? [];
          final confirmed = docs.where((d) => d.data()['reg_status'] != 'waitlisted').toList();
          final waitlisted = docs.where((d) => d.data()['reg_status'] == 'waitlisted').toList();

          if (docs.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_outline_rounded, size: 50, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No registrations yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              ]),
            ));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              if (_isPast)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                        'Camp is over — mark each donor\'s outcome below to issue badges & certificates.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900))),
                  ]),
                ),
              _sectionLabel('Confirmed (${confirmed.length})', color),
              const SizedBox(height: 8),
              ...confirmed.map((r) => _donorTile(r, color)),
              if (waitlisted.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionLabel('Waitlisted (${waitlisted.length})', Colors.orange.shade700),
                const SizedBox(height: 8),
                ...waitlisted.map((r) => _donorTile(r, color, isWaitlist: true)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) =>
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color));

  Widget _donorTile(QueryDocumentSnapshot<Map<String, dynamic>> reg, Color color, {bool isWaitlist = false}) {
    final d = reg.data();
    final intent = d['intent'] ?? 'donate';
    final isVolunteerIntent = intent == 'volunteer';
    final outcome = d['outcome'] ?? 'pending';
    final health = d['health'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(d['donor_name'] ?? 'Donor', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
              const SizedBox(width: 6),
              if ((d['blood_group'] ?? '').toString().isNotEmpty)
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(d['blood_group'], style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600))),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400),
            tooltip: 'Remove',
            onPressed: () => _reject(reg),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        const SizedBox(height: 4),
        Text(d['donor_phone'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _tag(isVolunteerIntent ? Icons.volunteer_activism_rounded : Icons.favorite_rounded,
              isVolunteerIntent ? 'Wants to volunteer' : 'Wants to donate', color),
          if ((d['time_slot'] ?? '').toString().isNotEmpty) _tag(Icons.schedule_rounded, d['time_slot'], Colors.grey.shade600),
          if (isWaitlist) _tag(Icons.hourglass_top_rounded, 'Waitlisted', Colors.orange.shade700),
        ]),
        if (health != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 4, children: [
            if (health['on_medication'] == true) _warnTag('On medication'),
            if (health['recent_illness'] == true) _warnTag('Recent illness'),
          ]),
        ],
        const SizedBox(height: 10),
        if (_isPast && outcome == 'pending')
          Row(children: [
            Expanded(child: _outcomeBtn('Donated', Colors.green, () => _markOutcome(reg, 'donated'))),
            const SizedBox(width: 6),
            Expanded(child: _outcomeBtn('Volunteered', Colors.blue, () => _markOutcome(reg, 'volunteered'))),
            const SizedBox(width: 6),
            Expanded(child: _outcomeBtn('No-show', Colors.grey, () => _markOutcome(reg, 'no_show'))),
          ])
        else if (outcome != 'pending')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: outcome == 'no_show' ? Colors.grey.shade100 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(outcome == 'no_show' ? Icons.remove_circle_outline_rounded : Icons.check_circle_rounded,
                  size: 14, color: outcome == 'no_show' ? Colors.grey.shade500 : Colors.green.shade600),
              const SizedBox(width: 5),
              Text(outcome == 'donated' ? 'Donated — badge issued'
                  : outcome == 'volunteered' ? 'Volunteered — certificate issued' : 'No-show',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: outcome == 'no_show' ? Colors.grey.shade600 : Colors.green.shade700)),
            ]),
          ),
      ]),
    );
  }

  Widget _tag(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(7)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color is MaterialColor ? color.shade700 : color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10.5, color: color is MaterialColor ? color.shade700 : color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _warnTag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(7)),
    child: Text(label, style: TextStyle(fontSize: 10.5, color: Colors.amber.shade800, fontWeight: FontWeight.w600)),
  );

  Widget _outcomeBtn(String label, MaterialColor color, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color.shade700,
      side: BorderSide(color: color.shade200),
      padding: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}
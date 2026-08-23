// PLACEMENT: lib/screens/hospital/tabs/hospital_home_tab.dart (overwrite existing file)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/nearby_sos_section.dart';
import '../../common/camps/my_camps_screen.dart';

class HospitalHomeTab extends StatefulWidget {
  final Map<String, dynamic>? hospitalData;
  final Color primaryColor;
  // Lets Quick Action buttons switch bottom-nav tabs without this widget
  // needing to own the PageController itself. Passed down from
  // HospitalDashboard; safe to omit (buttons just won't navigate).
  final void Function(int tabIndex)? onNavigate;
  const HospitalHomeTab({super.key, required this.hospitalData, required this.primaryColor, this.onNavigate});
  @override
  State<HospitalHomeTab> createState() => _HospitalHomeTabState();
}

class _HospitalHomeTabState extends State<HospitalHomeTab> with TickerProviderStateMixin {
  late AnimationController _headerController, _cardController;
  late Animation<double> _headerFade, _cardFade;
  late Animation<Offset> _headerSlide;
  final Set<String> _actingOnOffer = {}; // "$sosId-$donorUid" mid-transaction, to disable double-tap

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
    _cardFade = CurvedAnimation(parent: _cardController, curve: Curves.easeOut);
    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _cardController.forward(); });
  }

  @override
  void dispose() { _headerController.dispose(); _cardController.dispose(); super.dispose(); }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final data = widget.hospitalData;
    final hospitalName = data?['hospital_name'] ?? 'Hospital';
    final city = data?['city'] ?? '';
    final district = data?['district'] ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          SlideTransition(position: _headerSlide, child: FadeTransition(opacity: _headerFade,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
              child: Column(children: [
                // BloodLink logo + tagline
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    Image.asset('assets/images/bloodlink_logo.png', height: 32, width: 32),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('BloodLink',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      Text('Your Blood. Someone\'s Tomorrow.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 9, letterSpacing: 0.3)),
                    ]),
                  ]),
                  NotificationBell(uid: FirebaseAuth.instance.currentUser!.uid, primaryColor: Colors.white),
                ]),
                const SizedBox(height: 16),
                // Hospital info
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Welcome 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(hospitalName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.location_on, color: Colors.white.withValues(alpha: 0.8), size: 14),
                      const SizedBox(width: 4),
                      Text('$city${district.isNotEmpty ? ', $district' : ''}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    ]),
                  ])),
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2)),
                      child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 28)),
                ]),
              ]),
            ),
          )),

          const SizedBox(height: 20),

          // Stats row
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('blood_requests')
                  .where('hospital_uid', isEqualTo: _uid).snapshots(),
              builder: (context, snap) {
                final total = snap.data?.docs.length ?? 0;
                final active = snap.data?.docs.where((d) => (d.data() as Map)['status'] == 'active').length ?? 0;
                final fulfilled = snap.data?.docs.where((d) => (d.data() as Map)['status'] == 'fulfilled').length ?? 0;
                return Row(children: [
                  _buildStatCard('$total', 'Total\nRequests', Icons.list_alt_rounded, color),
                  const SizedBox(width: 12),
                  _buildStatCard('$active', 'Active\nRequests', Icons.pending_rounded, Colors.orange),
                  const SizedBox(width: 12),
                  _buildStatCard('$fulfilled', 'Fulfilled\nRequests', Icons.check_circle_rounded, Colors.green),
                ]);
              },
            ),
          )),

          const SizedBox(height: 20),

          // Active requests
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Active Blood Requests',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('blood_requests')
                      .where('hospital_uid', isEqualTo: _uid)
                      .where('status', isEqualTo: 'active').snapshots(),
                  builder: (ctx, snap) {
                    final count = snap.data?.docs.length ?? 0;
                    return count > 0 ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
                      child: Text('$count active', style: TextStyle(fontSize: 12, color: Colors.red.shade600, fontWeight: FontWeight.w600)),
                    ) : const SizedBox.shrink();
                  },
                ),
              ]),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('blood_requests')
                    .where('hospital_uid', isEqualTo: _uid)
                    .where('status', isEqualTo: 'active')
                    .orderBy('created_at', descending: true)
                    .limit(5).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2));
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                    return _buildEmptyState('No active requests', 'Post a blood request from the Requests tab');
                  return Column(children: snapshot.data!.docs.asMap().entries.map((entry) {
                    final d = entry.value.data() as Map<String, dynamic>;
                    return _buildRequestCard(d, entry.value.id, color);
                  }).toList());
                },
              ),
            ]),
          )),

          const SizedBox(height: 20),

          // Nearby SOS — donor/recipient/other-hospital broadcasts within
          // radius. View/Notify only (role != 'donor', so no accept
          // capability). Own requests hidden here since they're already
          // managed from the Requests tab above (and offer-review now lives
          // right on each card in "Active Blood Requests" above too).
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🚨 Nearby SOS Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              NearbySosSection(
                color: color,
                role: 'hospital',
                userData: widget.hospitalData,
                showOwnRequests: false,
              ),
            ]),
          )),

          const SizedBox(height: 20),

          // Quick actions
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Quick Actions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              Row(children: [
                _buildActionButton(Icons.add_circle_rounded, 'Post\nRequest', color, () => widget.onNavigate?.call(1)),
                const SizedBox(width: 12),
                _buildActionButton(Icons.search_rounded, 'Find\nDonors', Colors.purple, () => widget.onNavigate?.call(2)),

                const SizedBox(width: 12),
                _buildActionButton(Icons.history_rounded, 'Request\nHistory', Colors.orange, () => widget.onNavigate?.call(1)),

                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MyCampsScreen(
                      primaryColor: color,
                      organizerRole: 'hospital',
                      organizerName: hospitalName,
                      organizerPhone: data?['phone']?.toString(),
                    )));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.teal.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 3))]),
                    child: Column(children: [
                      Icon(Icons.campaign_rounded, color: Colors.teal, size: 26),
                      const SizedBox(height: 6),
                      Text('Blood\nCamps', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
                    ]),
                  ),
                )),
              ]),
            ]),
          )),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, height: 1.3)),
      ]),
    ));
  }

  Widget _buildRequestCard(Map<String, dynamic> d, String docId, Color color) {
    final String? sosId = d['sos_request_id'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.shade50),
              child: Center(child: Text(d['blood_group'] ?? '?',
                  style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold, fontSize: 13)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit${(d['units'] ?? 1) > 1 ? 's' : ''} needed',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A1A2E))),
            Text(d['patient_name'] ?? 'Patient', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            Text(d['urgency'] ?? 'Normal', style: TextStyle(
                color: (d['urgency'] ?? '') == 'Critical' ? Colors.red.shade600 : Colors.orange.shade600,
                fontSize: 11, fontWeight: FontWeight.w500)),
          ])),
          GestureDetector(
            onTap: () => _markFulfilled(docId),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('Fulfilled', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
          ),
        ]),
        if (sosId != null) _buildOffersSection(sosId, color),
      ]),
    );
  }

  // Donor-offer review, embedded right in the hospital's own request card.
  // Mirrors NearbySosSection's isMine review UI (pending offers get
  // Call/Message/Accept/Decline; accepted ones get a simple confirmed row
  // with Call) but deliberately does NOT reuse its "Mark done" button —
  // that only flips the sos_requests mirror, not this blood_requests doc,
  // which would desync the Requests tab / stats cards above. Fulfilling
  // stays on the "Fulfilled" button above, which already keeps both in sync.
  Widget _buildOffersSection(String sosId, Color color) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .collection('acceptances').orderBy('offered_at').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final pending = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'pending').toList();
        final accepted = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] != 'pending').toList();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('Offers to review', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            ...pending.map((doc) {
              final od = doc.data() as Map<String, dynamic>;
              final donorUid = doc.id;
              final busy = _actingOnOffer.contains('$sosId-$donorUid');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(od['donor_name'] ?? 'Donor', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${od['donor_blood_group'] ?? ''}'
                            '${od['donor_age'] != null ? ' • ${od['donor_age']} yrs' : ''}'
                            '${(od['donor_city'] ?? '').toString().isNotEmpty ? ' • ${od['donor_city']}' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ])),
                    GestureDetector(onTap: () => _callPhone(od['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.call, size: 16, color: color))),
                    GestureDetector(onTap: () => _messageDonor(od['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.sms_outlined, size: 16, color: color))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: busy ? null : () => _declineDonorOffer(sosId, donorUid, od),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400, side: BorderSide(color: Colors.red.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Decline', style: TextStyle(fontSize: 11)),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(
                      onPressed: busy ? null : () => _acceptDonorOffer(sosId, donorUid),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: busy
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Accept', style: TextStyle(fontSize: 11)),
                    )),
                  ]),
                ]),
              );
            }),
          ],
          if (accepted.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...accepted.map((doc) {
              final od = doc.data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade400),
                  const SizedBox(width: 6),
                  Expanded(child: Text(od['donor_name'] ?? 'Donor', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                  GestureDetector(
                    onTap: () => _callPhone(od['donor_phone'] ?? ''),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.call, size: 12, color: color),
                      const SizedBox(width: 3),
                      Text('Call', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              );
            }),
          ],
        ]);
      },
    );
  }

  Future<void> _callPhone(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open dialer for $phone'), backgroundColor: Colors.red.shade600));
      }
    }
  }

  Future<void> _messageDonor(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      await launchUrl(Uri(scheme: 'sms', path: phone));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open Messages for $phone'), backgroundColor: Colors.red.shade600));
      }
    }
  }

  // Same two-stage offer/accept flow as NearbySosSection's requester side:
  // re-checks a slot is still open, flips the offer to 'accepted', bumps
  // units_fulfilled, releases the donor's lock, and writes a verified
  // donation record (source: 'sos') so their History tab / badges / new
  // Hospital Certificate all update automatically.
  Future<void> _acceptDonorOffer(String sosId, String donorUid) async {
    HapticFeedback.mediumImpact();
    setState(() => _actingOnOffer.add('$sosId-$donorUid'));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(sosId);
    final offerRef = docRef.collection('acceptances').doc(donorUid);
    final donationRef = FirebaseFirestore.instance.collection('donors').doc(donorUid).collection('donations').doc();
    final donorDocRef = FirebaseFirestore.instance.collection('donors').doc(donorUid);

    try {
      Map<String, dynamic>? offerData;
      Map<String, dynamic>? requestData;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        requestData = snap.data() as Map<String, dynamic>;

        final offerSnap = await tx.get(offerRef);
        if (!offerSnap.exists) throw 'gone';
        offerData = offerSnap.data() as Map<String, dynamic>;
        if (offerData!['status'] == 'accepted') throw 'already';

        final unitsNeeded = _asInt(requestData!['units']);
        final unitsFulfilled = _asInt(requestData!['units_fulfilled'], fallback: 0);
        if (unitsFulfilled >= unitsNeeded) throw 'full';

        tx.update(offerRef, {
          'status': 'accepted',
          'accepted_at': FieldValue.serverTimestamp(),
          'donation_doc_id': donationRef.id,
        });
        tx.update(docRef, {'units_fulfilled': unitsFulfilled + 1});
        tx.update(donorDocRef, {'active_offer_request_id': null});
        tx.set(donationRef, {
          'type': 'Whole Blood',
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'date_display': DateFormat('dd MMM yyyy').format(DateTime.now()),
          'location': '${requestData!['hospital'] ?? requestData!['city'] ?? ''}'
              '${(requestData!['district'] ?? '').toString().isNotEmpty ? ', ${requestData!['district']}' : ''}',
          'units': 1,
          'source': 'sos',
          'verified': true,
          'request_id': sosId,
          'created_at': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 10));

      final donorName = offerData?['donor_name'] ?? 'The donor';
      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_help_accepted',
        'title': 'Your help is accepted! 🎉',
        'body': 'Thank you! Your donation for the ${requestData?['blood_group'] ?? ''} request has been confirmed.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$donorName confirmed! They have been notified.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        String msg;
        if (e.toString().contains('already')) {
          msg = 'This offer is already confirmed';
        } else if (e.toString().contains('full')) {
          msg = 'All units for this request are already covered';
        } else if (e is TimeoutException) {
          msg = 'Timed out — check Firestore rules allow this update';
        } else {
          msg = 'Could not confirm this donor: $e';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _actingOnOffer.remove('$sosId-$donorUid'));
    }
  }

  Future<void> _declineDonorOffer(String sosId, String donorUid, Map<String, dynamic> offerData) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline this offer?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('${offerData['donor_name'] ?? 'This donor'} will be notified so they can help someone else.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Decline')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final offerRef = FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .collection('acceptances').doc(donorUid);
      final donorDocRef = FirebaseFirestore.instance.collection('donors').doc(donorUid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final donorSnap = await tx.get(donorDocRef);
        String? currentActiveId;
        if (donorSnap.exists) {
          currentActiveId = donorSnap.data()?['active_offer_request_id'] as String?;
        }
        tx.delete(offerRef);
        if (currentActiveId == sosId) {
          tx.update(donorDocRef, {'active_offer_request_id': null});
        }
      });

      final requestSnap = await FirebaseFirestore.instance.collection('sos_requests').doc(sosId).get();
      final bloodGroup = (requestSnap.data()?['blood_group'] ?? '').toString();
      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_declined',
        'title': 'Offer declined',
        'body': 'Your offer to help the $bloodGroup request wasn\'t needed this time. Thanks for stepping up!',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    } catch (_) {}
  }

  static int _asInt(dynamic v, {int fallback = 1}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  Future<void> _markFulfilled(String docId) async {
    HapticFeedback.mediumImpact();
    final docRef = FirebaseFirestore.instance.collection('blood_requests').doc(docId);
    final snap = await docRef.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    await docRef.update({'status': 'fulfilled', 'fulfilled_at': FieldValue.serverTimestamp()});

    // Same sync as the Requests tab's own Mark Fulfilled — keeps the
    // donor-facing SOS mirror from staying "active" after this closes.
    final linkedSosId = data['sos_request_id'];
    if (linkedSosId != null) {
      await FirebaseFirestore.instance.collection('sos_requests').doc(linkedSosId)
          .update({'status': 'fulfilled'}).catchError((_) {});
    }
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(Icons.inbox_rounded, size: 40, color: Colors.grey.shade200),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w500)),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
      ]),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 3))]),
        child: Column(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
        ]),
      ),
    ));
  }
}
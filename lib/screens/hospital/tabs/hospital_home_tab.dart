import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
          // managed from the Requests tab above.
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
                _buildActionButton(Icons.local_hospital_rounded, 'Blood\nBanks', Colors.green, () => widget.onNavigate?.call(2)),
                const SizedBox(width: 12),
                _buildActionButton(Icons.history_rounded, 'Request\nHistory', Colors.orange, () => widget.onNavigate?.call(1)),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: 76,
                child: GestureDetector(
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
                ),
              ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Row(children: [
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
    );
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
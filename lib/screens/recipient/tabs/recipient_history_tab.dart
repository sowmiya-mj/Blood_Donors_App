import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class RecipientHistoryTab extends StatefulWidget {
  final Map<String, dynamic>? recipientData;
  final Color primaryColor;

  const RecipientHistoryTab({super.key, required this.recipientData, required this.primaryColor});

  @override
  State<RecipientHistoryTab> createState() => _RecipientHistoryTabState();
}

class _RecipientHistoryTabState extends State<RecipientHistoryTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // null = All
  String? _statusFilter;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    HapticFeedback.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open dialer')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open dialer')));
      }
    }
  }

  (Color, Color, String) _statusStyle(String status) {
    switch (status) {
      case 'fulfilled':
        return (Colors.green.shade50, Colors.green.shade600, 'Fulfilled');
      case 'expired':
        return (Colors.grey.shade100, Colors.grey.shade500, 'Expired');
      case 'active':
      default:
        return (Colors.orange.shade50, Colors.orange.shade700, 'Active');
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('MMM d, yyyy · h:mm a').format(ts.toDate());
  }

  void _showRequestDetail(String requestId, Map<String, dynamic> d, Color color) {
    HapticFeedback.lightImpact();
    final status = d['status'] as String? ?? 'active';
    final (bg, fg, label) = _statusStyle(status);
    final units = d['units'] ?? 1;
    final unitsFulfilled = d['units_fulfilled'] ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 48, height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
                  child: Center(child: Text(d['blood_group'] ?? '?',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['patient_name'] ?? 'Patient',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                Text(_formatDate(d['createdAt'] as Timestamp?), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            if ((d['hospital'] ?? '').toString().isNotEmpty)
              _detailRow(Icons.local_hospital_outlined, 'Hospital', d['hospital'], color),
            if ((d['address'] ?? '').toString().isNotEmpty)
              _detailRow(Icons.place_outlined, 'Address', d['address'], color),
            _detailRow(Icons.location_city_outlined, 'Location',
                [d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '), color),
            _detailRow(Icons.bloodtype_outlined, 'Units', '$unitsFulfilled of $units fulfilled', color),
            if ((d['phone'] ?? '').toString().isNotEmpty)
              _detailRow(Icons.phone_outlined, 'Contact given', d['phone'], color),

            const SizedBox(height: 16),
            const Text('Confirmed Donors', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('sos_requests').doc(requestId)
                    .collection('acceptances')
                    .where('status', isEqualTo: 'accepted')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2));
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text('No donors confirmed yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final donor = docs[i].data() as Map<String, dynamic>;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(donor['donor_name'] ?? 'Donor',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                            const SizedBox(height: 2),
                            Text(
                              '${donor['donor_blood_group'] ?? ''}'
                                  '${donor['donor_city'] != null && donor['donor_city'].toString().isNotEmpty ? ' • ${donor['donor_city']}' : ''}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ])),
                          GestureDetector(
                            onTap: () => _callPhone(donor['donor_phone']?.toString()),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                              child: Icon(Icons.call_rounded, color: Colors.green.shade600, size: 16),
                            ),
                          ),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)))),
      ]),
    );
  }

  Widget _buildFilterChip(String label, String? value, Color color) {
    final active = _statusFilter == value;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); setState(() => _statusFilter = value); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: active ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : Colors.grey.shade200),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildRequestCard(String id, Map<String, dynamic> d, Color color) {
    final status = d['status'] as String? ?? 'active';
    final (bg, fg, label) = _statusStyle(status);
    final units = d['units'] ?? 1;
    final unitsFulfilled = d['units_fulfilled'] ?? 0;

    return GestureDetector(
      onTap: () => _showRequestDetail(id, d, color),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 42, height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
                child: Center(child: Text(d['blood_group'] ?? '?',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['patient_name'] ?? 'Patient',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 2),
              Text(
                [d['city'], d['district']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.bloodtype_outlined, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text('$unitsFulfilled / $units units', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(width: 14),
            Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(_formatDate(d['createdAt'] as Timestamp?), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Request History',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 4),
              Text('Every SOS request you\'ve raised, past and present',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _buildFilterChip('All', null, color),
                  _buildFilterChip('Active', 'active', color),
                  _buildFilterChip('Fulfilled', 'fulfilled', color),
                  _buildFilterChip('Expired', 'expired', color),
                ]),
              ),
              const SizedBox(height: 16),
            ]),
          ),
          Expanded(
            child: _uid.isEmpty
                ? const SizedBox.shrink()
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('sos_requests')
                  .where('requester_uid', isEqualTo: _uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: color));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_rounded, size: 50, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No requests yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 15, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('Your SOS requests will show up here', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ]),
                    ),
                  );
                }

                var docs = snapshot.data!.docs;
                if (_statusFilter != null) {
                  docs = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == _statusFilter).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No ${_statusFilter ?? ''} requests', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                  );
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data() as Map<String, dynamic>;
                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 300 + i * 60),
                      builder: (context, val, child) => Opacity(
                        opacity: val,
                        child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child),
                      ),
                      child: _buildRequestCard(doc.id, d, color),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
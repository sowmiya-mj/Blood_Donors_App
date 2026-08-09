import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/geo_utils.dart';

class HospitalRequestsTab extends StatefulWidget {
  final Map<String, dynamic>? hospitalData;
  final Color primaryColor;
  const HospitalRequestsTab({super.key, required this.hospitalData, required this.primaryColor});
  @override
  State<HospitalRequestsTab> createState() => _HospitalRequestsTabState();
}

class _HospitalRequestsTabState extends State<HospitalRequestsTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  int _filterIndex = 0; // 0=All, 1=Active, 2=Fulfilled, 3=Cancelled

  final List<String> _filters = ['All', 'Active', 'Fulfilled', 'Cancelled'];
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() { _fadeController.dispose(); super.dispose(); }

  void _showPostRequestSheet() {
    String? selectedBloodGroup;
    String? selectedUrgency = 'Normal';
    int units = 1;
    bool isSaving = false;
    final patientCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];
    final urgencies = ['Normal', 'Urgent', 'Critical'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.75, maxChildSize: 0.92, minChildSize: 0.5,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: widget.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(Icons.add_circle_rounded, color: widget.primaryColor, size: 22)),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Post Blood Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    Text('Fill details to find donors', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Divider(height: 20, color: Colors.grey.shade100),
              Expanded(child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Blood group
                  const Text('Blood Group Required *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: bloodGroups.map((g) {
                    final sel = selectedBloodGroup == g;
                    return GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); setSheet(() => selectedBloodGroup = g); },
                      child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 58, height: 42,
                          decoration: BoxDecoration(
                              color: sel ? widget.primaryColor : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? widget.primaryColor : Colors.grey.shade200, width: sel ? 2 : 1)),
                          child: Center(child: Text(g, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700)))),
                    );
                  }).toList()),

                  const SizedBox(height: 20),

                  // Urgency
                  const Text('Urgency Level *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Row(children: urgencies.map((u) {
                    final sel = selectedUrgency == u;
                    final urgColor = u == 'Critical' ? Colors.red : u == 'Urgent' ? Colors.orange : Colors.green;
                    return Expanded(child: GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); setSheet(() => selectedUrgency = u); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(right: u != 'Cancelled' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                            color: sel ? urgColor.withValues(alpha: 0.1) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sel ? urgColor : Colors.grey.shade200, width: sel ? 2 : 1)),
                        child: Column(children: [
                          Icon(u == 'Critical' ? Icons.warning_rounded : u == 'Urgent' ? Icons.priority_high_rounded : Icons.check_circle_rounded,
                              color: sel ? urgColor : Colors.grey.shade400, size: 18),
                          const SizedBox(height: 4),
                          Text(u, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                              color: sel ? urgColor : Colors.grey.shade500)),
                        ]),
                      ),
                    ));
                  }).toList()),

                  const SizedBox(height: 20),

                  // Units
                  const Text('Units Required *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Row(children: [
                    GestureDetector(
                        onTap: () { if (units > 1) { HapticFeedback.lightImpact(); setSheet(() => units--); }},
                        child: Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.remove, size: 20))),
                    const SizedBox(width: 16),
                    Text('$units unit${units > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    const SizedBox(width: 16),
                    GestureDetector(
                        onTap: () { if (units < 10) { HapticFeedback.lightImpact(); setSheet(() => units++); }},
                        child: Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: widget.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.add, size: 20, color: widget.primaryColor))),
                  ]),

                  const SizedBox(height: 20),

                  // Patient name
                  _buildSheetField(patientCtrl, 'Patient Name', 'Enter patient name', Icons.person_outline, widget.primaryColor),
                  const SizedBox(height: 16),
                  _buildSheetField(notesCtrl, 'Additional Notes (optional)', 'Any special requirements', Icons.notes_rounded, widget.primaryColor, maxLines: 2),

                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade100)),
                    child: Row(children: [
                      Icon(Icons.campaign_outlined, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                          'This will also broadcast as an SOS to nearby donors so they can respond directly.',
                          style: TextStyle(fontSize: 11.5, color: Colors.blue.shade900))),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : () async {
                        if (selectedBloodGroup == null || patientCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Please fill required fields'),
                              backgroundColor: Colors.red.shade600,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                          return;
                        }
                        setSheet(() => isSaving = true);
                        try {
                          final city = widget.hospitalData?['city'] ?? '';
                          final district = widget.hospitalData?['district'] ?? '';
                          final state = widget.hospitalData?['state'] ?? '';

                          // Geocode the hospital's registered location so
                          // the mirrored SOS lands correctly on donors'
                          // radius search — same approach used for SOS
                          // created by Donor/Recipient/Blood Bank roles.
                          final point = await GeoUtils.geocode('$city, $district, $state');

                          final bloodReqRef = FirebaseFirestore.instance.collection('blood_requests').doc();
                          final sosRef = FirebaseFirestore.instance.collection('sos_requests').doc();
                          final batch = FirebaseFirestore.instance.batch();

                          // Internal ledger — hospital's own request history/reporting.
                          batch.set(bloodReqRef, {
                            'hospital_uid': _uid,
                            'hospital_name': widget.hospitalData?['hospital_name'] ?? '',
                            'city': city,
                            'district': district,
                            'state': state,
                            'blood_group': selectedBloodGroup,
                            'urgency': selectedUrgency,
                            'units': units,
                            'patient_name': patientCtrl.text.trim(),
                            'notes': notesCtrl.text.trim(),
                            'status': 'active',
                            'sos_request_id': sosRef.id, // link so status changes stay in sync
                            'created_at': FieldValue.serverTimestamp(),
                          });

                          // Donor-facing mirror — this is the doc
                          // NearbySosSection actually queries. Same schema
                          // as SOS created by other roles so the widget
                          // needs zero special-casing for hospital-origin
                          // requests.
                          batch.set(sosRef, {
                            'requester_uid': _uid,
                            'requester_role': 'hospital',
                            'patient_name': patientCtrl.text.trim(),
                            'blood_group': selectedBloodGroup,
                            'units': units,
                            'units_fulfilled': 0,
                            'hospital': widget.hospitalData?['hospital_name'] ?? '',
                            'city': city,
                            'district': district,
                            'phone': widget.hospitalData?['phone'] ?? '',
                            'status': 'active',
                            if (point != null) 'lat': point.lat,
                            if (point != null) 'lng': point.lng,
                            'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
                            'blood_request_id': bloodReqRef.id, // link back
                            'created_at': FieldValue.serverTimestamp(),
                          });

                          await batch.commit();

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: const Row(children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Blood request posted & broadcast to donors! 🩸'),
                                ]),
                                backgroundColor: Colors.green.shade600,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                          }
                        } catch (e) {
                          setSheet(() => isSaving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Could not post request: $e'),
                                backgroundColor: Colors.red.shade600,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text('Post Blood Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetField(TextEditingController ctrl, String label, String hint, IconData icon, Color color, {int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextField(controller: ctrl, maxLines: maxLines,
          decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              prefixIcon: maxLines == 1 ? Icon(icon, color: Colors.grey.shade400, size: 20) : null,
              filled: true, fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Blood Requests', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); _showPostRequestSheet(); },
                child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                    child: const Row(children: [
                      Icon(Icons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Post Request', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ])),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
              child: Row(children: _filters.asMap().entries.map((entry) {
                final active = _filterIndex == entry.key;
                return Expanded(child: GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); setState(() => _filterIndex = entry.key); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        color: active ? color : Colors.transparent,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(entry.value, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: active ? Colors.white : Colors.grey.shade500)),
                  ),
                ));
              }).toList()),
            ),
          ),
          const SizedBox(height: 16),

          // Requests list
          Expanded(child: StreamBuilder<QuerySnapshot>(
            stream: () {
              Query query = FirebaseFirestore.instance.collection('blood_requests')
                  .where('hospital_uid', isEqualTo: _uid)
                  .orderBy('created_at', descending: true);
              if (_filterIndex != 0) {
                query = query.where('status', isEqualTo: _filters[_filterIndex].toLowerCase());
              }
              return query.snapshots();
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.inbox_rounded, size: 60, color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Text('No ${_filterIndex == 0 ? '' : _filters[_filterIndex].toLowerCase()} requests',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                  Text('Tap "Post Request" to add one', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                ]));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, i) {
                  final doc = snapshot.data!.docs[i];
                  final d = doc.data() as Map<String, dynamic>;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 300 + i * 60),
                    builder: (context, val, child) => Opacity(opacity: val,
                        child: Transform.translate(offset: Offset(0, 20*(1-val)), child: child)),
                    child: _buildRequestItem(d, doc.id, color),
                  );
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  Widget _buildRequestItem(Map<String, dynamic> d, String docId, Color color) {
    final status = (d['status'] ?? 'active').toString();
    final urgency = d['urgency'] ?? 'Normal';
    final urgColor = urgency == 'Critical' ? Colors.red : urgency == 'Urgent' ? Colors.orange : Colors.green;
    final statusColor = status == 'active' ? Colors.blue : status == 'fulfilled' ? Colors.green : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.shade50),
              child: Center(child: Text(d['blood_group'] ?? '?',
                  style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold, fontSize: 13)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit${(d['units'] ?? 1) > 1 ? 's' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A2E))),
            Text(d['patient_name'] ?? 'Patient', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: urgColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(urgency, style: TextStyle(fontSize: 10, color: urgColor, fontWeight: FontWeight.w600))),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status.capitalize(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600))),
          ]),
        ]),
        if (d['notes'] != null && d['notes'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(d['notes'], style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
        if (status == 'active') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: GestureDetector(
                onTap: () => _updateStatus(docId, 'fulfilled'),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('Mark Fulfilled', style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.w600)))))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
                onTap: () => _updateStatus(docId, 'cancelled'),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('Cancel', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)))))),
          ]),
        ],
      ]),
    );
  }

  Future<void> _updateStatus(String docId, String status) async {
    HapticFeedback.mediumImpact();
    final docRef = FirebaseFirestore.instance.collection('blood_requests').doc(docId);
    try {
      final snap = await docRef.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};
      await docRef.update({'status': status, 'updated_at': FieldValue.serverTimestamp()});

      // Keep the donor-facing mirror in sync — otherwise a fulfilled or
      // cancelled hospital request would keep showing as "active" to
      // nearby donors indefinitely.
      final linkedSosId = data['sos_request_id'];
      if (linkedSosId != null) {
        await FirebaseFirestore.instance.collection('sos_requests').doc(linkedSosId)
            .update({'status': status == 'fulfilled' ? 'fulfilled' : 'expired'})
            .catchError((_) {});
      }
    } catch (_) {}
  }
}

extension StringExtension on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
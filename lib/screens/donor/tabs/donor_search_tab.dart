import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../common/sos/sos_bottom_sheet.dart';

class DonorSearchTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorSearchTab({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorSearchTab> createState() => _DonorSearchTabState();
}

class _DonorSearchTabState extends State<DonorSearchTab> with SingleTickerProviderStateMixin {
  String? _selectedBloodGroup;
  bool _isSearching = false, _sosActive = false;
  List<Map<String, dynamic>> _results = [];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  final TextEditingController _cityCtrl = TextEditingController();
  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() { _fadeController.dispose(); _cityCtrl.dispose(); super.dispose(); }

  Future<void> _searchDonors() async {
    if (_selectedBloodGroup == null) return;
    setState(() { _isSearching = true; _results = []; });
    try {
      Query query = FirebaseFirestore.instance.collection('donors')
          .where('blood_group', isEqualTo: _selectedBloodGroup)
          .where('is_available', isEqualTo: true);
      if (_cityCtrl.text.isNotEmpty) query = query.where('city', isEqualTo: _cityCtrl.text.trim());
      final snap = await query.limit(20).get();
      setState(() { _results = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList(); });
    } catch (_) {} finally { setState(() => _isSearching = false); }
  }

  Future<void> _sendSOS() async {
    HapticFeedback.heavyImpact();
    setState(() => _sosActive = true);
    try {
      await FirebaseFirestore.instance.collection('sos_requests').add({
        'blood_group': widget.donorData?['blood_group'] ?? _selectedBloodGroup ?? 'Unknown',
        'patient_name': widget.donorData?['name'] ?? 'Unknown',
        'city': widget.donorData?['city'] ?? '',
        'units': 1, 'status': 'active',
        'requester_uid': FirebaseAuth.instance.currentUser?.uid,
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8), Text('SOS Alert sent!')]),
          backgroundColor: Colors.green.shade600, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (_) { setState(() => _sosActive = false); }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return SafeArea(child: FadeTransition(opacity: _fadeAnim, child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Search & Request', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 4),
        Text('Find donors or send emergency SOS', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        // SOS Button
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.85,
                maxChildSize: 0.95,
                minChildSize: 0.5,
                builder: (_, controller) => SOSBottomSheet(
                  userData: widget.donorData, // or recipientData
                  primaryColor: widget.primaryColor,
                  onSOSSent: () {
                    setState(() => _sosActive = true);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Row(children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('SOS Alert sent to nearby donors!'),
                      ]),
                      backgroundColor: Colors.green.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                ),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: _sosActive
                    ? [Colors.grey.shade400, Colors.grey.shade300]
                    : [color, color.withValues(alpha: 0.8)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: _sosActive ? [] : [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 6))]),
            child: Column(children: [
              Icon(Icons.sos_rounded, color: Colors.white, size: 40),
              const SizedBox(height: 8),
              Text(_sosActive ? 'SOS Sent! Help is on the way 🙏' : 'SOS — Emergency Blood Needed',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(_sosActive ? 'Nearby donors have been notified' : 'Tap to alert nearby donors instantly',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(height: 28),
        const Text('Find a Donor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        const Text('Blood Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: _bloodGroups.map((g) {
          final sel = _selectedBloodGroup == g;
          return GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedBloodGroup = g); },
            child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                width: 58, height: 42,
                decoration: BoxDecoration(
                    color: sel ? color : Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1),
                    boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)] : []),
                child: Center(child: Text(g, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.grey.shade700)))),
          );
        }).toList()),
        const SizedBox(height: 16),
        TextField(controller: _cityCtrl,
            decoration: InputDecoration(hintText: 'Search by city (optional)',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.location_city_outlined, color: Colors.grey.shade400),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
                onPressed: _selectedBloodGroup == null || _isSearching ? null : _searchDonors,
                icon: _isSearching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search_rounded),
                label: Text(_isSearching ? 'Searching...' : 'Search Donors'),
                style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0))),
        const SizedBox(height: 20),
        if (_results.isNotEmpty) ...[
          Text('${_results.length} donors found', style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          ..._results.asMap().entries.map((e) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 300 + e.key * 80),
            builder: (context, val, child) => Opacity(opacity: val, child: Transform.translate(offset: Offset(0, 20*(1-val)), child: child)),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
                    child: Center(child: Text(e.value['blood_group'] ?? '?', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.value['name'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
                  Text('${e.value['city'] ?? ''} • Age ${e.value['age'] ?? 'N/A'}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Available', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
            ),
          )),
        ],
      ]),
    )));
  }
}


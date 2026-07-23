import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DonorHomeTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorHomeTab({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorHomeTab> createState() => _DonorHomeTabState();
}

class _DonorHomeTabState extends State<DonorHomeTab> with TickerProviderStateMixin {
  bool _isAvailable = true;
  bool _togglingAvailability = false;
  late AnimationController _headerController, _statsController, _sosController, _cardController;
  late Animation<double> _headerFade, _statsFade, _sosPulse, _cardFade;
  late Animation<Offset> _headerSlide;
  int _displayDonations = 0, _displayLives = 0;
  final int _totalDonations = 3, _totalLives = 9;

  @override
  void initState() {
    super.initState();
    _isAvailable = widget.donorData?['is_available'] ?? true;
    _headerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _statsController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _sosController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _headerFade = CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
    _statsFade = CurvedAnimation(parent: _statsController, curve: Curves.easeOut);
    _sosPulse = Tween<double>(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _sosController, curve: Curves.easeInOut));
    _cardFade = CurvedAnimation(parent: _cardController, curve: Curves.easeOut);
    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) { _statsController.forward(); _startCountUp(); }});
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _cardController.forward(); });
  }

  void _startCountUp() {
    const steps = 30;
    for (int i = 0; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: 50 * i), () {
        if (mounted) setState(() {
          _displayDonations = (_totalDonations * i / steps).round();
          _displayLives = (_totalLives * i / steps).round();
        });
      });
    }
  }

  @override
  void dispose() {
    _headerController.dispose(); _statsController.dispose();
    _sosController.dispose(); _cardController.dispose();
    super.dispose();
  }

  Future<void> _toggleAvailability(bool value) async {
    HapticFeedback.mediumImpact();
    setState(() => _togglingAvailability = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('donors').doc(uid).update({'is_available': value});
        setState(() => _isAvailable = value);
      }
    } catch (_) {} finally { setState(() => _togglingAvailability = false); }
  }

  String _greeting() { final h = DateTime.now().hour; return h < 12 ? 'Morning' : h < 17 ? 'Afternoon' : 'Evening'; }

  @override
  Widget build(BuildContext context) {
    final name = widget.donorData?['name'] ?? 'Donor';
    final bloodGroup = widget.donorData?['blood_group'] ?? 'N/A';
    final city = widget.donorData?['city'] ?? '';
    final color = widget.primaryColor;
    final firstName = name.split(' ').first;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          SlideTransition(position: _headerSlide, child: FadeTransition(opacity: _headerFade,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Good ${_greeting()}, 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(firstName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.location_on, color: Colors.white.withValues(alpha: 0.8), size: 14),
                      const SizedBox(width: 4),
                      Text(city, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    ]),
                  ])),
                  Container(width: 60, height: 60,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2)),
                      child: Center(child: Text(bloodGroup, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle,
                        color: _isAvailable ? Colors.greenAccent : Colors.white.withValues(alpha: 0.5))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_isAvailable ? 'Available to Donate' : 'Not Available',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(_isAvailable ? 'You can receive donation requests' : 'Toggle on when ready',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                    ])),
                    _togglingAvailability
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Switch(value: _isAvailable, onChanged: _toggleAvailability,
                        activeColor: Colors.greenAccent, activeTrackColor: Colors.white.withValues(alpha: 0.3),
                        inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.white.withValues(alpha: 0.2)),
                  ]),
                ),
              ]),
            ),
          )),
          const SizedBox(height: 20),
          // Stats
          FadeTransition(opacity: _statsFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _buildStatCard('$_displayDonations', 'Donations', Icons.favorite, color),
              const SizedBox(width: 12),
              _buildStatCard('$_displayLives', 'Lives Helped', Icons.people_rounded, Colors.orange),
              const SizedBox(width: 12),
              _buildStatCard('O+', 'Compatible', Icons.bloodtype, Colors.purple),
            ]),
          )),
          const SizedBox(height: 20),
          // Next donation card
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(children: [
                Container(width: 50, height: 50,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(Icons.calendar_today_rounded, color: color, size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Next Eligible Donation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text('You can donate again in 45 days', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text('45 days', style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.w600))),
              ]),
            ),
          )),
          const SizedBox(height: 16),
          // SOS Nearby
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🚨 Nearby SOS Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('sos_requests')
                    .where('status', isEqualTo: 'active').limit(3).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Icon(Icons.check_circle_outline, color: Colors.green.shade400, size: 28),
                        const SizedBox(width: 12),
                        Text('No active SOS requests nearby 🎉', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                      ]),
                    );
                  }
                  return Column(children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final isMyRequest = data['requester_uid'] ==
                        FirebaseAuth.instance.currentUser?.uid;
                    return ScaleTransition(scale: _sosPulse, child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                shape: BoxShape.circle),
                            child: Text(data['blood_group'] ?? 'O+',
                                style: TextStyle(color: color,
                                    fontWeight: FontWeight.bold, fontSize: 13))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            "${data['patient_name'] ?? 'Patient'} (${data['blood_group'] ?? 'N/A'} blood) ",
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "${data['city'] ?? ''} • ${data['units'] ?? 1} unit${(data['units'] ?? 1) > 1 ? 's' : ''} needed",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ])),
                        isMyRequest
                            ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text('Active',
                                style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)))
                            : ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Help',
                                style: TextStyle(fontSize: 12))),
                      ]),
                    ));
                  }).toList());
                },
              ),
            ]),
          )),
          const SizedBox(height: 16),
          // Quick Actions
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              Row(children: [
                _buildActionButton(Icons.local_hospital_rounded, 'Find Blood\nBank', Colors.blue, () {}),
                const SizedBox(width: 12),
                _buildActionButton(Icons.campaign_rounded, 'Blood\nCamps', Colors.orange, () {}),
                const SizedBox(width: 12),
                _buildActionButton(Icons.workspace_premium_rounded, 'My\nBadges', Colors.purple, () {}),
                const SizedBox(width: 12),
                _buildActionButton(Icons.share_rounded, 'Share\nApp', Colors.green, () {}),
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
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]),
    ));
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
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
        ]),
      ),
    ));
  }
}


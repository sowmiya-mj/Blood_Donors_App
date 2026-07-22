import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecipientHomeTab extends StatefulWidget {
  final Map<String, dynamic>? recipientData;
  final Color primaryColor;

  const RecipientHomeTab({super.key, required this.recipientData, required this.primaryColor});

  @override
  State<RecipientHomeTab> createState() => _RecipientHomeTabState();
}

class _RecipientHomeTabState extends State<RecipientHomeTab>
    with TickerProviderStateMixin {
  bool _sosActive = false;
  late AnimationController _headerController;
  late AnimationController _sosController;
  late AnimationController _cardController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _sosPulse;
  late Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _sosController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _cardController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _headerFade = CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
    _sosPulse = Tween<double>(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _sosController, curve: Curves.easeInOut));
    _cardFade = CurvedAnimation(parent: _cardController, curve: Curves.easeOut);

    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _cardController.forward();
    });
  }

  @override
  void dispose() {
    _headerController.dispose();
    _sosController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _sendSOS() async {
    HapticFeedback.heavyImpact();
    final data = widget.recipientData;
    try {
      await FirebaseFirestore.instance.collection('sos_requests').add({
        'blood_group': data?['blood_group'] ?? 'Unknown',
        'patient_name': data?['name'] ?? 'Unknown',
        'city': data?['city'] ?? '',
        'district': data?['district'] ?? '',
        'state': data?['state'] ?? '',
        'units': 1,
        'status': 'active',
        'requester_uid': FirebaseAuth.instance.currentUser?.uid,
        'created_at': FieldValue.serverTimestamp(),
      });
      setState(() => _sosActive = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('SOS sent! Nearby donors have been notified.')),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send SOS: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final data = widget.recipientData;
    final name = data?['name'] ?? 'User';
    final bloodGroup = data?['blood_group'] ?? 'N/A';
    final city = data?['city'] ?? '';
    final firstName = name.split(' ').first;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          SlideTransition(
            position: _headerSlide,
            child: FadeTransition(
              opacity: _headerFade,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hello, 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(firstName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.location_on, color: Colors.white.withValues(alpha: 0.8), size: 14),
                      const SizedBox(width: 4),
                      Text(city, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    ]),
                  ])),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: Center(child: Text(bloodGroup,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  ),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // SOS Button
          FadeTransition(
            opacity: _cardFade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScaleTransition(
                scale: _sosActive ? const AlwaysStoppedAnimation(1.0) : _sosPulse,
                child: GestureDetector(
                  onTap: _sosActive ? null : _sendSOS,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    decoration: BoxDecoration(
                      gradient: _sosActive
                          ? LinearGradient(colors: [Colors.green.shade400, Colors.green.shade300])
                          : const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFB71C1C)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (_sosActive ? Colors.green : const Color(0xFFE53935)).withValues(alpha: 0.4),
                          blurRadius: 20, offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(children: [
                      Icon(_sosActive ? Icons.check_circle_rounded : Icons.sos_rounded,
                          color: Colors.white, size: 44),
                      const SizedBox(height: 8),
                      Text(
                        _sosActive ? 'SOS Sent! Help is Coming 🙏' : 'SOS Emergency',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sosActive ? 'Donors near you have been alerted' : 'Tap to alert nearby donors instantly',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Blood Banks nearby
          FadeTransition(
            opacity: _cardFade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Nearby Blood Banks',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('blood_banks')
                      .limit(3)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _buildEmptyBloodBank(color);
                    }
                    return Column(
                      children: snapshot.data!.docs.asMap().entries.map((entry) {
                        final i = entry.key;
                        final bank = entry.value.data() as Map<String, dynamic>;
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(milliseconds: 300 + i * 100),
                          builder: (context, val, child) => Opacity(
                            opacity: val,
                            child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child),
                          ),
                          child: _buildBloodBankCard(bank, color),
                        );
                      }).toList(),
                    );
                  },
                ),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          // Active requests
          FadeTransition(
            opacity: _cardFade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('My Active Requests',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('sos_requests')
                      .where('requester_uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                      .where('status', isEqualTo: 'active')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Icon(Icons.inbox_rounded, color: Colors.grey.shade300, size: 28),
                          const SizedBox(width: 12),
                          Text('No active requests',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                        ]),
                      );
                    }
                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return _buildRequestCard(d, color);
                      }).toList(),
                    );
                  },
                ),
              ]),
            ),
          ),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _buildEmptyBloodBank(Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.local_hospital_outlined, color: Colors.grey.shade300, size: 28),
        const SizedBox(width: 12),
        Text('No blood banks registered nearby', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      ]),
    );
  }

  Widget _buildBloodBankCard(Map<String, dynamic> bank, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
          child: Icon(Icons.local_hospital_rounded, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bank['bank_name'] ?? 'Blood Bank',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
          Text('${bank['city'] ?? ''} • ${bank['district'] ?? ''}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Open', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> d, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(children: [
        Icon(Icons.sos_rounded, color: Colors.red, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SOS • ${d['blood_group'] ?? ''} needed',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
          Text('${d['city'] ?? ''} • Active',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
          child: const Text('Active', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

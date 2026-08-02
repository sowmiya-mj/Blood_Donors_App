import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../widgets/notification_bell.dart';

class BloodBankHomeTab extends StatefulWidget {
  final Map<String, dynamic>? bankData;
  final Color primaryColor;
  final VoidCallback onDataUpdated;

  const BloodBankHomeTab({
    super.key,
    required this.bankData,
    required this.primaryColor,
    required this.onDataUpdated,
  });

  @override
  State<BloodBankHomeTab> createState() => _BloodBankHomeTabState();
}

class _BloodBankHomeTabState extends State<BloodBankHomeTab> with TickerProviderStateMixin {
  late AnimationController _headerController, _cardController;
  late Animation<double> _headerFade, _cardFade;
  late Animation<Offset> _headerSlide;

  static const List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const int _lowStockThreshold = 5;

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

  Map<String, int> get _stock {
    final raw = widget.bankData?['stock'] as Map<String, dynamic>? ?? {};
    return {for (final g in _bloodGroups) g: (raw[g] ?? 0) as int};
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final data = widget.bankData;
    final bankName = data?['bank_name'] ?? 'Blood Bank';
    final city = data?['city'] ?? '';
    final district = data?['district'] ?? '';
    final stock = _stock;
    final lowStockGroups = stock.entries.where((e) => e.value < _lowStockThreshold).map((e) => e.key).toList();
    final totalUnits = stock.values.fold<int>(0, (a, b) => a + b);

    return SafeArea(
      child: RefreshIndicator(
        color: color,
        onRefresh: () async => widget.onDataUpdated(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Header — matches hospital_home_tab pattern exactly
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
                  // Blood bank info
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Welcome 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(bankName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                        child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 28)),
                  ]),
                ]),
              ),
            )),

            const SizedBox(height: 20),

            // Total units stat card
            FadeTransition(opacity: _cardFade, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total Units in Stock', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('$totalUnits', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                  ])),
                  Icon(Icons.inventory_2_rounded, color: Colors.white.withValues(alpha: 0.85), size: 40),
                ]),
              ),
            )),

            const SizedBox(height: 16),

            // Low stock alert banner
            if (lowStockGroups.isNotEmpty)
              FadeTransition(opacity: _cardFade, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Low stock: ${lowStockGroups.join(', ')} (below $_lowStockThreshold units)',
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                    )),
                  ]),
                ),
              )),

            // Blood group stock — responsive fixed-size cards (won't stretch on desktop)
            FadeTransition(opacity: _cardFade, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock by Blood Group', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _bloodGroups.map((group) {
                    final units = stock[group] ?? 0;
                    final isLow = units < _lowStockThreshold;
                    final cardColor = isLow ? Colors.red : (units < 15 ? Colors.orange : Colors.green);
                    return Container(
                      width: 135, height: 100,
                      decoration: BoxDecoration(
                        color: cardColor.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardColor.shade200),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(group, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cardColor.shade700)),
                        const SizedBox(height: 4),
                        Text('$units units', style: TextStyle(fontSize: 11, color: cardColor.shade600)),
                      ]),
                    );
                  }).toList(),
                ),
              ]),
            )),

            const SizedBox(height: 28),

            // Nearby SOS requests
            FadeTransition(opacity: _cardFade, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nearby SOS Requests', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('sos_requests')
                      .where('status', isEqualTo: 'active')
                      .orderBy('createdAt', descending: true)
                      .limit(5)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      // ignore: avoid_print
                      print('SOS stream error: ${snapshot.error}');
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
                        child: Text(
                          'Could not load SOS requests.\n${snapshot.error}',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2));
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return _buildEmptyState('No active SOS requests', 'Emergency requests near you will show up here');
                    }
                    return Column(children: docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
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
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                            child: Center(child: Text(d['blood_group'] ?? '?',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade600))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(d['patient_name'] ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${d['units'] ?? ''} units • ${d['city'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ])),
                        ]),
                      );
                    }).toList());
                  },
                ),
              ]),
            )),

            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
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
}
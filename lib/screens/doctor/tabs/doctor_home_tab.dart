import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/notification_bell.dart';


class DoctorHomeTab extends StatefulWidget {
  final Map<String, dynamic>? doctorData;
  final Color primaryColor;
  final void Function(int tabIndex) onNavigateToTab;
  const DoctorHomeTab({
    super.key,
    required this.doctorData,
    required this.primaryColor,
    required this.onNavigateToTab,
  });
  @override
  State<DoctorHomeTab> createState() => _DoctorHomeTabState();
}

class _DoctorHomeTabState extends State<DoctorHomeTab> with TickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final data = widget.doctorData;
    final name = data?['name'] ?? 'Doctor';
    final specialization = data?['specialization'] ?? '';
    final affiliation = data?['affiliation'] ?? '';
    final city = data?['city'] ?? '';
    final district = data?['district'] ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header — matches hospital/blood bank pattern exactly
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
                // Doctor info
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Welcome 👋', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                      child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 28)),
                ]),
              ]),
            ),
          )),

          const SizedBox(height: 20),

          // Doctor info card
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildInfoRow(Icons.medical_information_outlined, 'Specialization', specialization, color),
                if (affiliation.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.local_hospital_outlined, 'Affiliation', affiliation, color),
                ],
              ]),
            ),
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
                _buildActionButton(Icons.search_rounded, 'Find\nDonors', color,
                        () => widget.onNavigateToTab(1)),
                const SizedBox(width: 12),
                _buildActionButton(Icons.map_rounded, 'Nearby\nMap', Colors.purple,
                        () => widget.onNavigateToTab(2)),
                const SizedBox(width: 12),
                _buildActionButton(Icons.person_rounded, 'My\nProfile', Colors.orange,
                        () => widget.onNavigateToTab(3)),
              ]),
            ]),
          )),

          const SizedBox(height: 20),

          // Info banner
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(
                    'Use "Find Donors" to search available donors near your clinic and view them on a map.',
                    style: TextStyle(color: color, fontSize: 12.5, height: 1.4))),
              ]),
            ),
          )),

          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value.isEmpty ? 'Not set' : value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      ])),
    ]);
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

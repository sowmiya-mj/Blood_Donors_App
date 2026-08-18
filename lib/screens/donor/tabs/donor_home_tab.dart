import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/nearby_sos_section.dart';
import '../donor_hospitals_bloodbanks_map_screen.dart';
import '../donor_blood_camps_screen.dart';

class DonorHomeTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  // Optional — lets the parent DonorDashboard jump to another tab when a
  // Quick Action is tapped. If not supplied, those actions fall back to a
  // "coming soon" style snackbar instead of doing nothing silently.
  final VoidCallback? onNavigateToBloodBanks;
  final VoidCallback? onNavigateToBadges;

  const DonorHomeTab({
    super.key,
    required this.donorData,
    required this.primaryColor,
    this.onNavigateToBloodBanks,
    this.onNavigateToBadges,
  });

  @override
  State<DonorHomeTab> createState() => _DonorHomeTabState();
}

class _DonorHomeTabState extends State<DonorHomeTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _togglingAvailability = false;
  bool _autoOffInFlight = false;
  late AnimationController _headerController, _statsController, _sosController, _cardController;
  late Animation<double> _headerFade, _statsFade, _sosPulse, _cardFade;
  late Animation<Offset> _headerSlide;
  int _displayDonations = 0, _displayLives = 0;

  // Guards the count-up animation so it only plays once per screen visit,
  // triggered by the first real Firestore snapshot rather than a fixed
  // timer (the old hardcoded-number version didn't need this).
  bool _statsAnimated = false;

  // Minimum gap (days) before a donor is eligible again, by donation type.
  // Whole Blood/Platelets/Plasma/Double Red Cells follow standard donation
  // interval guidelines. Unknown/missing type falls back to Whole Blood's 90.
  static const Map<String, int> _donationGapDays = {
    'Whole Blood': 90,
    'Platelets': 14,
    'Plasma': 28,
    'Double Red Cells': 112,
  };

  @override
  void initState() {
    super.initState();
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
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _cardController.forward(); });
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _maybeAnimateStats(int totalDonations, int totalLives) {
    if (_statsAnimated) return;
    _statsAnimated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _statsController.forward();
      _startCountUp(totalDonations, totalLives);
    });
  }

  void _startCountUp(int totalDonations, int totalLives) {
    const steps = 30;
    for (int i = 0; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: 50 * i), () {
        if (mounted) setState(() {
          _displayDonations = (totalDonations * i / steps).round();
          _displayLives = (totalLives * i / steps).round();
        });
      });
    }
  }

  // Latest donation (any source — this is a safety/eligibility check, not
  // a rewards check, so self-reported entries count here even though they
  // don't count toward badges) determines the next eligible date.
  Map<String, dynamic> _computeEligibility(List<QueryDocumentSnapshot> donations) {
    if (donations.isEmpty) return {'eligible': true, 'daysLeft': 0};
    final latest = donations.first.data() as Map<String, dynamic>;
    final rawDate = latest['date'];
    final dateStr = rawDate is String ? rawDate : null;
    final type = latest['type'] as String? ?? 'Whole Blood';
    final lastDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
    if (lastDate == null) return {'eligible': true, 'daysLeft': 0};
    final gap = _donationGapDays[type] ?? 90;
    final eligibleDate = lastDate.add(Duration(days: gap));
    final daysLeft = eligibleDate.difference(DateTime.now()).inDays;
    return {'eligible': daysLeft <= 0, 'daysLeft': daysLeft > 0 ? daysLeft : 0};
  }

  // "Available to Donate" is now linked to eligibility: when the donor
// isn't eligible yet (recent donation, gap not passed), the toggle is
// auto-forced off and locked — tapping it shows why instead of doing
// nothing. Reads live from Firestore on both streams so it's always
// correct even if state was set from another device or by Mark Done
// on an SOS request.
  Widget _buildAvailabilityToggle() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('donors').doc(_uid).collection('donations')
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, donSnap) {
        final donations = donSnap.data?.docs ?? [];
        final eligibility = _computeEligibility(donations);
        final isEligible = eligibility['eligible'] as bool;
        final daysLeft = eligibility['daysLeft'] as int;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('donors').doc(_uid).snapshots(),
          builder: (context, docSnap) {
            final data = docSnap.data?.data() as Map<String, dynamic>?;
            final isAvailable = data?['is_available'] ?? false;

            if (!isEligible && isAvailable && !_autoOffInFlight) {
              _autoOffInFlight = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => _forceUnavailable());
            }

            final switchWidget = Switch(
              value: isAvailable,
              onChanged: isEligible ? _toggleAvailability : null,
              activeColor: Colors.greenAccent,
              activeTrackColor: Colors.white.withValues(alpha: 0.3),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            );

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
              child: Row(children: [
                Icon(
                  isEligible ? Icons.circle : Icons.lock_rounded,
                  color: isAvailable ? Colors.greenAccent : Colors.white.withValues(alpha: 0.6),
                  size: isEligible ? 10 : 16,
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(!isEligible ? 'Not Available' : (isAvailable ? 'Available to Donate' : 'Not Available'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                    !isEligible
                        ? "Locked — eligible in $daysLeft day${daysLeft == 1 ? '' : 's'}"
                        : (isAvailable ? 'You can receive donation requests' : 'Toggle on when ready'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                  ),
                ])),
                _togglingAvailability
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : (isEligible
                    ? switchWidget
                    : GestureDetector(
                    onTap: () => _showLockedSnack(daysLeft),
                    child: Opacity(opacity: 0.5, child: IgnorePointer(child: switchWidget)))),
              ]),
            );
          },
        );
      },
    );
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

      }
    } catch (_) {} finally { setState(() => _togglingAvailability = false); }
  }

  Future<void> _forceUnavailable() async {
    if (_uid.isEmpty) { _autoOffInFlight = false; return; }
    try {
      await FirebaseFirestore.instance.collection('donors').doc(_uid).update({'is_available': false});
    } catch (_) {} finally { _autoOffInFlight = false; }
  }

  void _showLockedSnack(int daysLeft) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(daysLeft > 0
          ? "You'll be eligible again in $daysLeft day${daysLeft == 1 ? '' : 's'} — availability unlocks automatically then."
          : "Not eligible to donate yet."),
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _greeting() { final h = DateTime.now().hour; return h < 12 ? 'Morning' : h < 17 ? 'Afternoon' : 'Evening'; }

  Future<void> _shareApp() async {
    HapticFeedback.lightImpact();
    await Share.share(
      "I'm on BloodLink — a platform that connects blood donors with people who need it urgently. "
          "Join me and help save lives with a single donation. 🩸",
      subject: 'Save lives with BloodLink',
    );
  }

  void _showComingSoon(String feature) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$feature is coming soon!'),
      backgroundColor: widget.primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                // BloodLink logo + tagline row
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
                  // Notification bell placeholder
                  NotificationBell(uid: FirebaseAuth.instance.currentUser!.uid, primaryColor: Colors.white),
                ]),
                const SizedBox(height: 16),
                // User greeting row
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
                _buildAvailabilityToggle(),
              ]),
            ),
          )),


          const SizedBox(height: 20),

          // Stats + Next Eligible Donation — both driven live from the
          // donor's donations subcollection (same source History tab reads).
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('donors')
                .doc(_uid)
                .collection('donations')
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              final donations = snapshot.data?.docs ?? [];
              final totalDonations = donations.length;
              final totalLives = totalDonations * 3;

              if (snapshot.connectionState != ConnectionState.waiting) {
                _maybeAnimateStats(totalDonations, totalLives);
              }

              final eligibility = _computeEligibility(donations);
              final bool isEligible = eligibility['eligible'] as bool;
              final int daysLeft = eligibility['daysLeft'] as int;

              return Column(children: [
                FadeTransition(opacity: _statsFade, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _buildStatCard('$_displayDonations', 'Donations', Icons.favorite, color),
                    const SizedBox(width: 12),
                    _buildStatCard('$_displayLives', 'Lives Helped', Icons.people_rounded, Colors.orange),
                    const SizedBox(width: 12),
                    _buildCompatibleCard(bloodGroup),
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
                          decoration: BoxDecoration(
                              color: (isEligible ? Colors.green : color).withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: Icon(
                              isEligible ? Icons.check_circle_rounded : Icons.calendar_today_rounded,
                              color: isEligible ? Colors.green : color, size: 24)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Next Eligible Donation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                        const SizedBox(height: 4),
                        Text(
                          totalDonations == 0
                              ? 'No donations logged yet — you\'re eligible now!'
                              : isEligible
                              ? 'You\'re eligible to donate now!'
                              : 'You can donate again in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ])),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: isEligible ? Colors.green.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(
                              isEligible ? 'Eligible' : '$daysLeft days',
                              style: TextStyle(fontSize: 12,
                                  color: isEligible ? Colors.green.shade600 : Colors.orange.shade700,
                                  fontWeight: FontWeight.w600))),
                    ]),
                  ),
                )),
              ]);
            },
          ),

          const SizedBox(height: 16),
          // SOS Nearby — radius-filtered (50km), shared across all roles
          FadeTransition(opacity: _cardFade, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🚨 Nearby SOS Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),
              NearbySosSection(color: color, role: 'donor', userData: widget.donorData),
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
                _buildActionButton(Icons.location_on_outlined, 'view\nMap', Colors.blue,
                        () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DonorHospitalsBloodBanksMapScreen(primaryColor: widget.primaryColor)))),
                const SizedBox(width: 12),
                _buildActionButton(Icons.campaign_rounded, 'Blood\nCamps', Colors.orange,
                        () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DonorBloodCampsScreen(donorData: widget.donorData, primaryColor: widget.primaryColor)))),
                const SizedBox(width: 12),
                _buildActionButton(Icons.workspace_premium_rounded, 'My\nBadges', Colors.purple,
                        () => widget.onNavigateToBadges != null
                        ? widget.onNavigateToBadges!()
                        : _showComingSoon('Badges')),
                const SizedBox(width: 12),
                _buildActionButton(Icons.share_rounded, 'Share\nApp', Colors.green, _shareApp),
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

  List<String> _getCanReceiveFrom(String bloodGroup) {
    switch (bloodGroup) {
      case 'O-': return ['O-'];
      case 'O+': return ['O-', 'O+'];
      case 'A-': return ['O-', 'A-'];
      case 'A+': return ['O-', 'O+', 'A-', 'A+'];
      case 'B-': return ['O-', 'B-'];
      case 'B+': return ['O-', 'O+', 'B-', 'B+'];
      case 'AB-': return ['O-', 'A-', 'B-', 'AB-'];
      case 'AB+': return ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'];
      default: return [];
    }
  }

  List<String> _getCompatibleTypes(String bloodGroup) {
    switch (bloodGroup) {
      case 'O-': return ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'];
      case 'O+': return ['O+', 'A+', 'B+', 'AB+'];
      case 'A-': return ['A-', 'A+', 'AB-', 'AB+'];
      case 'A+': return ['A+', 'AB+'];
      case 'B-': return ['B-', 'B+', 'AB-', 'AB+'];
      case 'B+': return ['B+', 'AB+'];
      case 'AB-': return ['AB-', 'AB+'];
      case 'AB+': return ['AB+'];
      default: return [];
    }
  }

  Widget _buildCompatibleCard(String bloodGroup) {
    final types = _getCompatibleTypes(bloodGroup);
    return Expanded(
      child: GestureDetector(
        onTap: () => _showCompatibilitySheet(bloodGroup),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.purple.withValues(alpha: 0.1),
                blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(children: [
            Icon(Icons.bloodtype, color: Colors.purple, size: 22),
            const SizedBox(height: 6),
            Text('${types.length}', style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple)),
            Text('Compatible', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
        ),
      ),
    );
  }

  void _showCompatibilitySheet(String bloodGroup) {
    final donateTo = _getCompatibleTypes(bloodGroup);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
                    child: Icon(Icons.bloodtype, color: Colors.purple.shade600, size: 24)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Blood Compatibility',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  Text('Your blood group: $bloodGroup',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ]),
              ]),
              const SizedBox(height: 20),
              Text('🩸 You can donate to:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: donateTo.map((g) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.shade200)),
                    child: Text(g, style: TextStyle(
                        color: Colors.purple.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
                  )).toList()),
              const SizedBox(height: 20),
              Text('💉 You can receive from:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: _getCanReceiveFrom(bloodGroup).map((g) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200)),
                    child: Text(g, style: TextStyle(
                        color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 14)),
                  )).toList()),
              const SizedBox(height: 24),
              if (bloodGroup == 'O-')
                Container(padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.star_rounded, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('You are a Universal Donor! Your blood can save anyone.',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500))),
                    ])),
              if (bloodGroup == 'AB+')
                Container(padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.star_rounded, color: Colors.blue.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text('You are a Universal Recipient! You can receive blood from anyone.',
                          style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.w500))),
                    ])),
              const SizedBox(height: 16),
            ]),
      ),
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
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3)),
        ]),
      ),
    ));
  }
}
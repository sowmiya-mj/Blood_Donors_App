import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DonorHistoryTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorHistoryTab({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorHistoryTab> createState() => _DonorHistoryTabState();
}

class _DonorHistoryTabState extends State<DonorHistoryTab>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Badge celebration shower — fires once per NEW badge crossed, not on
  // every rebuild. We track the last count we've already celebrated for
  // so a stream re-emit (e.g. from an unrelated field change) doesn't
  // replay the shower.
  late AnimationController _showerController;
  bool _showering = false;
  int? _lastSeenCount;

  final List<String> _donationTypes = [
    'Whole Blood', 'Platelets', 'Plasma', 'Double Red Cells'
  ];

  static const List<Map<String, Object>> _badges = [
    {'icon': '🏅', 'label': '1st Donation', 'target': 1},
    {'icon': '⭐', 'label': '3 Donations', 'target': 3},
    {'icon': '🏆', 'label': '5 Donations', 'target': 5},
    {'icon': '💎', 'label': '10 Donations', 'target': 10},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _showerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _showerController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Checks whether `count` newly crosses a badge target that the
  // previous known count hadn't reached yet. Called from inside the
  // StreamBuilder — schedules the actual setState for AFTER the current
  // build finishes (can't setState mid-build).
  void _maybeCelebrate(int count) {
    if (_lastSeenCount == null) {
      // First build this session — just remember where we are, don't
      // celebrate for donations that were already there before we opened
      // this screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _lastSeenCount = count);
      });
      return;
    }
    if (count <= _lastSeenCount!) return;

    final crossedNewBadge = _badges.any((b) =>
    (b['target'] as int) > _lastSeenCount! && (b['target'] as int) <= count);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() {
        _lastSeenCount = count;
        if (crossedNewBadge) _showering = true;
      });
      if (crossedNewBadge) {
        HapticFeedback.mediumImpact();
        _showerController.forward(from: 0);
        await Future.delayed(const Duration(milliseconds: 1800));
        if (mounted) setState(() => _showering = false);
      }
    });
  }

  // Add Donation bottom sheet
  void _showAddDonationSheet() {
    final locationCtrl = TextEditingController();
    DateTime? selectedDate;
    String? selectedType;
    int units = 1;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: widget.primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(Icons.favorite_rounded, color: widget.primaryColor, size: 22)),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Log Donation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    Text('Add your donation record', style: TextStyle(fontSize: 12, color: Colors.grey)),
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

                  // Self-reported notice — sets expectations up front instead
                  // of surprising the donor with an "unverified" tag later.
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200)),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                          "Manually logged donations are marked self-reported. Donations completed through an SOS request are auto-verified.",
                          style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900))),
                    ]),
                  ),
                  const SizedBox(height: 18),

                  const Text('Donation Type *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10,
                      children: _donationTypes.map((type) {
                        final sel = selectedType == type;
                        return GestureDetector(
                          onTap: () { HapticFeedback.lightImpact(); setSheetState(() => selectedType = type); },
                          child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                  color: sel ? widget.primaryColor : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: sel ? widget.primaryColor : Colors.grey.shade200, width: sel ? 2 : 1)),
                              child: Text(type, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                                  color: sel ? Colors.white : Colors.grey.shade700))),
                        );
                      }).toList()),

                  const SizedBox(height: 20),

                  const Text('Donation Date *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(primary: widget.primaryColor)),
                            child: child!),
                      );
                      if (picked != null) setSheetState(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selectedDate != null ? widget.primaryColor : Colors.grey.shade200)),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, color: Colors.grey.shade400, size: 20),
                        const SizedBox(width: 12),
                        Text(selectedDate != null
                            ? DateFormat('dd MMM yyyy').format(selectedDate!)
                            : 'Select donation date',
                            style: TextStyle(fontSize: 14,
                                color: selectedDate != null ? const Color(0xFF1A1A2E) : Colors.grey.shade400)),
                        const Spacer(),
                        Icon(Icons.arrow_drop_down, color: widget.primaryColor),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text('Hospital / Location *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: locationCtrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Apollo Hospital, Chennai',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      prefixIcon: Icon(Icons.local_hospital_outlined, color: Colors.grey.shade400, size: 20),
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text('Units Donated', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Row(children: [
                    GestureDetector(
                        onTap: () { if (units > 1) { HapticFeedback.lightImpact(); setSheetState(() => units--); }},
                        child: Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.remove, size: 20))),
                    const SizedBox(width: 16),
                    Text('$units unit${units > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    const SizedBox(width: 16),
                    GestureDetector(
                        onTap: () { if (units < 5) { HapticFeedback.lightImpact(); setSheetState(() => units++); }},
                        child: Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: widget.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.add, size: 20, color: widget.primaryColor))),
                  ]),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : () async {
                        if (selectedType == null || selectedDate == null || locationCtrl.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Please fill all required fields'),
                              backgroundColor: Colors.red.shade600,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                          return;
                        }
                        setSheetState(() => isSaving = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('donors')
                              .doc(_uid)
                              .collection('donations')
                              .add({
                            'type': selectedType,
                            'date': DateFormat('yyyy-MM-dd').format(selectedDate!),
                            'date_display': DateFormat('dd MMM yyyy').format(selectedDate!),
                            'location': locationCtrl.text.trim(),
                            'units': units,
                            'source': 'manual',
                            'verified': false,
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: const Row(children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Donation logged successfully! 🎉'),
                                ]),
                                backgroundColor: Colors.green.shade600,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                          }
                        } catch (e) {
                          setSheetState(() => isSaving = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text('Save Donation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    return SafeArea(
      child: Stack(children: [
        FadeTransition(
          opacity: _fadeAnim,
          child: StreamBuilder<QuerySnapshot>(
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
              final totalMl = totalDonations * 450;

              // Badges (and the celebration shower) only count VERIFIED
              // donations — self-reported entries are for the donor's own
              // tracking, but shouldn't earn achievements. Someone could
              // type in 10 fake entries otherwise and hit the 💎 badge
              // without ever donating.
              final verifiedCount = donations.where((doc) =>
              (doc.data() as Map<String, dynamic>)['verified'] == true).length;

              if (snapshot.connectionState != ConnectionState.waiting) {
                _maybeCelebrate(verifiedCount);
              }

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Donation History',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                            const SizedBox(height: 4),
                            Text('Your journey of saving lives',
                                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () { HapticFeedback.lightImpact(); _showAddDonationSheet(); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Log Donation', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  _buildBadgesRow(color, verifiedCount),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _buildSummaryItem('$totalDonations', 'Total\nDonations'),
                      Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.3)),
                      _buildSummaryItem('$totalLives', 'Lives\nImpacted'),
                      Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.3)),
                      _buildSummaryItem('${totalMl}ml', 'Blood\nDonated'),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  const Text('History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 12),

                  if (snapshot.connectionState == ConnectionState.waiting)
                    Center(child: CircularProgressIndicator(color: color))
                  else if (donations.isEmpty)
                    Center(child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        Icon(Icons.favorite_border_rounded, size: 60, color: Colors.grey.shade200),
                        const SizedBox(height: 12),
                        Text('No donations logged yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 6),
                        Text('Tap "Log Donation" to add your first!', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                      ]),
                    ))
                  else
                    ...donations.asMap().entries.map((entry) {
                      final i = entry.key;
                      final data = entry.value.data() as Map<String, dynamic>;
                      final docId = entry.value.id;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 300 + i * 80),
                        builder: (context, val, child) => Opacity(
                            opacity: val, child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child)),
                        child: _buildDonationCard(data, docId, color),
                      );
                    }),
                ]),
              );
            },
          ),
        ),

        // Badge celebration shower — full-screen, tap-through overlay.
        if (_showering)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _showerController,
                builder: (context, _) => CustomPaint(
                  painter: _ConfettiPainter(_showerController.value),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildBadgesRow(Color color, int totalDonations) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Badges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
        const SizedBox(width: 6),
        Icon(Icons.verified_rounded, size: 13, color: color.withValues(alpha: 0.6)),
      ]),
      Text('Based on verified donations only', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
      const SizedBox(height: 12),
      Row(children: _badges.map((b) {
        final earned = totalDonations >= (b['target'] as int);
        return Expanded(child: TweenAnimationBuilder<double>(
          tween: Tween(begin: earned ? 0.5 : 1.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: earned ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: earned ? color.withValues(alpha: 0.3) : Colors.grey.shade200)),
            child: Column(children: [
              Text(b['icon'] as String, style: TextStyle(fontSize: 22,
                  color: earned ? null : const Color.fromRGBO(0, 0, 0, 0.3))),
              const SizedBox(height: 4),
              Text(b['label'] as String, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: earned ? color : Colors.grey.shade400, fontWeight: FontWeight.w500)),
            ]),
          ),
        ));
      }).toList()),
    ]);
  }

  Widget _buildSummaryItem(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
    ]);
  }

  Widget _buildDonationCard(Map<String, dynamic> data, String docId, Color color) {
    final isVerified = data['verified'] == true;
    return Dismissible(
      key: Key(docId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Donation', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('Remove this donation record?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Delete')),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        await FirebaseFirestore.instance
            .collection('donors').doc(_uid)
            .collection('donations').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Donation record deleted'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(children: [
          Container(width: 46, height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
              child: Icon(Icons.favorite_rounded, color: color, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(data['type'] ?? 'Whole Blood',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: isVerified ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isVerified ? Icons.verified_rounded : Icons.edit_note_rounded,
                      size: 10, color: isVerified ? Colors.green.shade600 : Colors.grey.shade500),
                  const SizedBox(width: 2),
                  Text(isVerified ? 'Verified' : 'Self-reported',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                          color: isVerified ? Colors.green.shade600 : Colors.grey.shade500)),
                ]),
              ),
            ]),
            const SizedBox(height: 2),
            Text(data['location'] ?? '', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 2),
            Text(data['date_display'] ?? data['date'] ?? '',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
          ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${data['units'] ?? 1} Unit',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// Lightweight confetti shower — no external package needed. Draws ~40
/// falling particles (emoji-style colored circles + a few stars) whose
/// vertical position, drift, and rotation are all pure functions of the
/// animation value (0→1) and a per-particle seed, so it's fully
/// deterministic and cheap to repaint every frame.
class _ConfettiPainter extends CustomPainter {
  final double progress;
  _ConfettiPainter(this.progress);

  static final List<Color> _colors = [
    Colors.red.shade400, Colors.pink.shade300, Colors.amber.shade400,
    Colors.purple.shade300, Colors.orange.shade400, Colors.teal.shade300,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7); // fixed seed → stable particle layout per shower
    const particleCount = 40;

    for (int i = 0; i < particleCount; i++) {
      final seedX = rnd.nextDouble();
      final delay = rnd.nextDouble() * 0.3; // stagger start times
      final speed = 0.7 + rnd.nextDouble() * 0.6;
      final drift = (rnd.nextDouble() - 0.5) * 60;
      final colorIdx = rnd.nextInt(_colors.length);
      final isStar = rnd.nextBool();
      final particleSize = 5 + rnd.nextDouble() * 5;

      final t = ((progress - delay) * speed).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final dx = seedX * size.width + drift * t;
      final dy = -20 + t * (size.height + 40);
      final opacity = t > 0.75 ? (1 - t) * 4 : 1.0;
      final rotation = t * 6.28 * (rnd.nextBool() ? 1 : -1);

      final paint = Paint()..color = _colors[colorIdx].withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);
      if (isStar) {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: particleSize, height: particleSize), paint);
      } else {
        canvas.drawCircle(Offset.zero, particleSize / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.progress != progress;
}
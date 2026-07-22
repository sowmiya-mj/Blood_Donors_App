import 'package:flutter/material.dart';

class DonorHistoryTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorHistoryTab({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorHistoryTab> createState() => _DonorHistoryTabState();
}

class _DonorHistoryTabState extends State<DonorHistoryTab> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _mockHistory = [
    {'date': '15 Mar 2025', 'location': 'Apollo Hospital, Chennai', 'units': 1, 'type': 'Whole Blood'},
    {'date': '10 Sep 2024', 'location': 'GH Blood Bank, Coimbatore', 'units': 1, 'type': 'Platelets'},
    {'date': '22 Jan 2024', 'location': 'AIIMS Blood Centre, Delhi', 'units': 1, 'type': 'Whole Blood'},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() { _fadeController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Donation History',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text('Your journey of saving lives', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),

            // Badges
            _buildBadgesRow(color),
            const SizedBox(height: 24),

            // Summary card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _buildSummaryItem('${_mockHistory.length}', 'Total\nDonations'),
                Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.3)),
                _buildSummaryItem('${_mockHistory.length * 3}', 'Lives\nImpacted'),
                Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.3)),
                _buildSummaryItem('${_mockHistory.length * 450}ml', 'Blood\nDonated'),
              ]),
            ),
            const SizedBox(height: 24),

            const Text('History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 12),

            if (_mockHistory.isEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.history_rounded, size: 60, color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Text('No donations yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                ]),
              ))
            else
              ..._mockHistory.asMap().entries.map((entry) {
                final i = entry.key;
                final h = entry.value;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 400 + i * 100),
                  builder: (context, val, child) => Opacity(
                    opacity: val,
                    child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child),
                  ),
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
                        Text(h['type'] ?? 'Whole Blood',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
                        const SizedBox(height: 2),
                        Text(h['location'] ?? '', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(h['date'] ?? '', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      ])),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text('${h['units']} Unit', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                );
              }),
          ]),
        ),
      ),
    );
  }

  Widget _buildBadgesRow(Color color) {
    final badges = [
      {'icon': '🏅', 'label': '1st Donation', 'earned': true},
      {'icon': '⭐', 'label': '3 Donations', 'earned': true},
      {'icon': '🏆', 'label': '5 Donations', 'earned': false},
      {'icon': '💎', 'label': '10 Donations', 'earned': false},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Badges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      Row(children: badges.map((b) {
        final earned = b['earned'] as bool;
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
      Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
    ]);
  }
}

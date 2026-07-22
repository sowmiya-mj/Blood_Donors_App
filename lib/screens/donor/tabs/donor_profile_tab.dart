import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DonorProfileTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  final VoidCallback onDataUpdated;

  const DonorProfileTab({
    super.key,
    required this.donorData,
    required this.primaryColor,
    required this.onDataUpdated,
  });

  @override
  State<DonorProfileTab> createState() => _DonorProfileTabState();
}

class _DonorProfileTabState extends State<DonorProfileTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      // TODO: Navigate to role selection
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final data = widget.donorData;
    final name = data?['name'] ?? 'Donor';
    final email = data?['email'] ?? '';
    final phone = data?['phone'] ?? '';
    final bloodGroup = data?['blood_group'] ?? 'N/A';
    final age = data?['age']?.toString() ?? 'N/A';
    final city = data?['city'] ?? '';
    final district = data?['district'] ?? '';
    final state = data?['state'] ?? '';

    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Profile Header ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.2),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5), width: 3),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'D',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Text(bloodGroup,
                          style: TextStyle(
                              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(email,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text('Verified Donor',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                  ]),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Personal Info
                const Text('Personal Info',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),
                _buildInfoCard([
                  _InfoItem(Icons.person_outline, 'Full Name', name),
                  _InfoItem(Icons.bloodtype_outlined, 'Blood Group', bloodGroup),
                  _InfoItem(Icons.cake_outlined, 'Age', '$age years'),
                  _InfoItem(Icons.phone_outlined, 'Phone', phone),
                ], color),

                const SizedBox(height: 20),

                // Location
                const Text('Location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),
                _buildInfoCard([
                  _InfoItem(Icons.location_city_outlined, 'City', city),
                  _InfoItem(Icons.map_outlined, 'District', district),
                  _InfoItem(Icons.flag_outlined, 'State', state),
                ], color),

                const SizedBox(height: 20),

                // Account Actions
                const Text('Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),

                _buildActionTile(Icons.edit_rounded, 'Edit Profile', color, () {}),
                const SizedBox(height: 10),
                _buildActionTile(Icons.download_rounded, 'Download Certificate', Colors.green, () {}),
                const SizedBox(height: 10),
                _buildActionTile(Icons.share_rounded, 'Share App', Colors.blue, () {}),
                const SizedBox(height: 10),
                _buildActionTile(Icons.logout_rounded, 'Logout', Colors.red, _logout,
                    isDestructive: true),

                const SizedBox(height: 30),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoItem> items, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Icon(item.icon, color: color, size: 20),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(item.value.isEmpty ? 'Not set' : item.value,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E))),
              ]),
            ]),
          ),
          if (i < items.length - 1)
            Divider(height: 1, color: Colors.grey.shade100, indent: 50),
        ]);
      }).toList()),
    );
  }

  Widget _buildActionTile(IconData icon, String label, Color color,
      VoidCallback onTap, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                  color: isDestructive ? Colors.red : const Color(0xFF1A1A2E)))),
          Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 16),
        ]),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  _InfoItem(this.icon, this.label, this.value);
}

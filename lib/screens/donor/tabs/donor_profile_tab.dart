import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../donor_edit_profile_screen.dart';
import '../../auth/role_selection_screen.dart';

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
  bool _isUpdatingLocation = false;
  bool _uploadingPhoto = false;

  // Kept in sync with donor_history_tab.dart's badge tiers (same verified-
  // donation thresholds) so the badge shown here always matches the History
  // tab's badge shelf.
  static const List<Map<String, Object>> _badges = [
    {'icon': '🏅', 'label': '1st Donation', 'target': 1},
    {'icon': '⭐', 'label': '3 Donations', 'target': 3},
    {'icon': '🏆', 'label': '5 Donations', 'target': 5},
    {'icon': '💎', 'label': '10 Donations', 'target': 10},
  ];

  Map<String, Object>? _highestEarnedBadge(int verifiedCount) {
    Map<String, Object>? highest;
    for (final b in _badges) {
      if ((b['target'] as int) <= verifiedCount) highest = b;
    }
    return highest;
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

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

  Future<void> _updateMyLocation() async {
    if (_isUpdatingLocation) return;
    HapticFeedback.lightImpact();
    setState(() => _isUpdatingLocation = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied. Enable it in app settings to update.', isError: true);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('Turn on device location (GPS) and try again.', isError: true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
      );

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance.collection('donors').doc(uid).update({
        'last_lat': position.latitude,
        'last_lng': position.longitude,
        'location_updated_at': FieldValue.serverTimestamp(),
      });

      _showSnack('Location updated — nearby searches now use your current spot.');
      widget.onDataUpdated();
    } catch (e) {
      _showSnack('Could not fetch location. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Profile photo ─────────────────────────────────────────────
  Future<void> _showPhotoOptions() async {
    final hasPhoto = widget.donorData?['photo_path'] != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
              title: Text('Remove Photo', style: TextStyle(color: Colors.red.shade400)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null) return;
    if (action == 'remove') { await _removePhoto(); return; }
    await _pickAndUpload(action == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: source, maxWidth: 800, imageQuality: 80);
    if (file == null) return;
    if (_uid.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _uploadingPhoto = true);
    try {
      // Copy into the app's own permanent documents folder — the path
      // image_picker returns points at a temp/cache location that isn't
      // guaranteed to survive OS storage cleanup.
      final docsDir = await getApplicationDocumentsDirectory();
      final savedPath = '${docsDir.path}/donor_photo_$_uid.jpg';
      await File(file.path).copy(savedPath);

      await FirebaseFirestore.instance.collection('donors').doc(_uid).update({'photo_path': savedPath});
      widget.onDataUpdated();
      _showSnack('Profile photo updated!');
    } catch (_) {
      _showSnack('Could not save photo. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_uid.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _uploadingPhoto = true);
    try {
      final path = widget.donorData?['photo_path'] as String?;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      await FirebaseFirestore.instance.collection('donors').doc(_uid).update({'photo_path': FieldValue.delete()});
      widget.onDataUpdated();
      _showSnack('Profile photo removed');
    } catch (_) {
      _showSnack('Could not remove photo. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Share / logout ────────────────────────────────────────────
  Future<void> _shareApp() async {
    HapticFeedback.lightImpact();
    await Share.share(
      "I'm on BloodLink — a platform that connects blood donors with people who need it urgently. "
          "Join me and help save lives with a single donation. 🩸",
      subject: 'Save lives with BloodLink',
    );
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
      if (!mounted) return;
      // Clear the entire navigation stack so Back never returns to the
      // dashboard after logout, and land on role selection.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            (route) => false,
      );
    }
  }

  // ── Certificate ────────────────────────────────────────────────
  // Only ever called when verifiedCount > 0 (button is hidden otherwise).
  // Uses verified donations only — same integrity reasoning as badges,
  // since self-reported entries can't be confirmed by a third party.
  Future<void> _downloadCertificate(String name, String bloodGroup, int verifiedCount) async {
    HapticFeedback.lightImpact();
    try {
      final doc = pw.Document();
      final issueDate = DateFormat('d MMMM yyyy').format(DateTime.now());
      final livesHelped = verifiedCount * 3;

      // Logo is bundled as an app asset (see pubspec.yaml note). If it's
      // ever missing for some reason, the certificate still renders fine
      // without it rather than crashing the whole download.
      pw.MemoryImage? logo;
      try {
        final logoBytes = await rootBundle.load('assets/images/bloodlink_logo.png');
        logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {
        logo = null;
      }

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Container(
          padding: const pw.EdgeInsets.all(40),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.red400, width: 3)),
          child: pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, width: 70, height: 70),
                  pw.SizedBox(height: 10),
                ],
                pw.Text('BloodLink', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
                pw.Text("Your Blood. Someone's Tomorrow.", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(height: 30),
                pw.Text('CERTIFICATE OF APPRECIATION', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 30),
                pw.Text('This certificate is proudly presented to', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                pw.SizedBox(height: 10),
                pw.Text(name, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
                pw.SizedBox(height: 10),
                pw.Text('Blood Group: $bloodGroup', style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 20),
                pw.Text(
                  'In recognition of $verifiedCount verified blood donation${verifiedCount == 1 ? '' : 's'},\n'
                      'helping save up to $livesHelped ${livesHelped == 1 ? 'life' : 'lives'}.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 13),
                ),
                pw.SizedBox(height: 40),
                pw.Text('Issued on $issueDate', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(height: 24),
                // Signature-line style sign-off, replacing the old em-dash
                // ("—") which the default PDF font can't render — it was
                // showing up as a tofu box (□) instead of a dash.
                pw.Container(width: 130, height: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 6),
                pw.Text('BloodLink Team', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
              ],
            ),
          ),
        ),
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'BloodLink_Certificate_${name.replaceAll(' ', '_')}.pdf',
      );
    } catch (_) {
      _showSnack('Could not generate certificate. Try again.', isError: true);
    }
  }

  void _showBadgeSnack(Map<String, Object> badge, int verifiedCount) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${badge['icon']} ${badge['label']} — $verifiedCount verified donation${verifiedCount == 1 ? '' : 's'}. '
          'See the History tab for the full badge shelf.'),
      backgroundColor: widget.primaryColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
    final photoPath = data?['photo_path'] as String?;
    final hasLocalPhoto = photoPath != null && File(photoPath).existsSync();
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('donors').doc(_uid).collection('donations')
              .where('verified', isEqualTo: true)
              .snapshots(),
          builder: (context, snap) {
            final verifiedCount = snap.data?.docs.length ?? 0;
            final badge = _highestEarnedBadge(verifiedCount);

            return SingleChildScrollView(
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
                    GestureDetector(
                      onTap: _uploadingPhoto ? null : _showPhotoOptions,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.5, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.2),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5), width: 3),
                              image: hasLocalPhoto
                                  ? DecorationImage(image: FileImage(File(photoPath!)), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: _uploadingPhoto
                                ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : (!hasLocalPhoto
                                ? Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'D',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                              ),
                            )
                                : null),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: Text(bloodGroup,
                                  style: TextStyle(
                                      color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Positioned(
                            bottom: 0, left: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5)),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 12),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showBadgeSnack(badge, verifiedCount),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(badge['icon'] as String, style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ],
                    ]),
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

                    const SizedBox(height: 10),

                    GestureDetector(
                      onTap: _updateMyLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: color.withValues(alpha: 0.25)),
                        ),
                        child: Row(children: [
                          _isUpdatingLocation
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                              : Icon(Icons.my_location_rounded, color: color, size: 22),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Update My Location', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                            Text('Moved cities? Refresh so hospitals find you correctly',
                                style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
                          ])),
                        ]),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Account Actions
                    const Text('Account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 12),

                    _buildActionTile(Icons.edit_rounded, 'Edit Profile', color, () async {
                      final updated = await Navigator.push<bool>(context, MaterialPageRoute(
                          builder: (_) => DonorEditProfileScreen(donorData: widget.donorData, primaryColor: color)));
                      if (updated == true) widget.onDataUpdated();
                    }),
                    if (verifiedCount > 0) ...[
                      const SizedBox(height: 10),
                      _buildActionTile(Icons.download_rounded, 'Download Certificate', Colors.green,
                              () => _downloadCertificate(name, bloodGroup, verifiedCount)),
                    ],
                    const SizedBox(height: 10),
                    _buildActionTile(Icons.share_rounded, 'Share App', Colors.blue, _shareApp),
                    const SizedBox(height: 10),
                    _buildActionTile(Icons.logout_rounded, 'Logout', Colors.red, _logout,
                        isDestructive: true),

                    const SizedBox(height: 30),
                  ]),
                ),
              ]),
            );
          },
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
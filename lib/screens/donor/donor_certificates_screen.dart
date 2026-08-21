import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'lifetime_certificate_helper.dart';
import '../,,/../common/camps/camp_certificate_helper.dart';

// Every certificate here is regenerated on-the-fly at download time from
// Firestore metadata rather than stored as a file — same no-Storage
// approach already used for donor photos. Nothing is uploaded anywhere;
// each tap just re-runs the same PDF generation the organizer's device
// (or the Profile tab, for the lifetime one) already runs.
class DonorCertificatesScreen extends StatelessWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;

  const DonorCertificatesScreen({
    super.key,
    required this.donorData,
    required this.primaryColor,
  });

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final name = (donorData?['name'] ?? 'Donor').toString();
    final bloodGroup = (donorData?['blood_group'] ?? 'N/A').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('My Certificates'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('donors')
            .doc(_uid)
            .collection('donations')
            .where('verified', isEqualTo: true)
            .snapshots(),
        builder: (context, donSnap) {
          final donationDocs = donSnap.data?.docs ?? [];
          final verifiedCount = donationDocs.length;
          final campDonationDocs =
          donationDocs.where((d) => (d.data() as Map)['source'] == 'camp').toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('donors')
                .doc(_uid)
                .collection('camp_participations')
                .snapshots(),
            builder: (context, volSnap) {
              final volunteerDocs = volSnap.data?.docs ?? [];

              final campCerts = <_CampCertItem>[
                ...campDonationDocs.map(_CampCertItem.fromDonation),
                ...volunteerDocs.map(_CampCertItem.fromParticipation),
              ]..sort((a, b) => b.date.compareTo(a.date));

              final isLoading = donSnap.connectionState == ConnectionState.waiting ||
                  volSnap.connectionState == ConnectionState.waiting;

              if (isLoading) {
                return Center(child: CircularProgressIndicator(color: primaryColor));
              }

              if (verifiedCount == 0 && campCerts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.workspace_premium_outlined, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('No certificates yet',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Donate or volunteer at a camp to earn one!',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12), textAlign: TextAlign.center),
                    ]),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (verifiedCount > 0) ...[
                    _certTile(
                      context: context,
                      icon: Icons.workspace_premium_rounded,
                      iconColor: Colors.amber.shade700,
                      title: 'Lifetime Achievement Certificate',
                      subtitle: '$verifiedCount verified donation${verifiedCount == 1 ? '' : 's'}',
                      onTap: () => LifetimeCertificateHelper.generateAndShare(
                        donorName: name,
                        bloodGroup: bloodGroup,
                        verifiedCount: verifiedCount,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (campCerts.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('Camp Certificates',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                    ),
                    ...campCerts.map((c) => _certTile(
                      context: context,
                      icon: c.isDonation ? Icons.favorite_rounded : Icons.volunteer_activism_rounded,
                      iconColor: c.isDonation ? primaryColor : Colors.blue.shade600,
                      title: c.isDonation ? 'Donation Certificate' : 'Volunteer Certificate',
                      subtitle: '${c.campTitle} · ${DateFormat('d MMM yyyy').format(c.date)}',
                      onTap: () => CampCertificateHelper.generateAndShare(
                        donorName: name,
                        campTitle: c.campTitle,
                        organizerName: c.organizerName,
                        date: c.date,
                        type: c.isDonation ? CertificateType.donation : CertificateType.volunteer,
                      ),
                    )),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _certTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            HapticFeedback.lightImpact();
            try {
              await onTap();
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not generate certificate. Try again.')),
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: iconColor.withValues(alpha: 0.12)),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
              Icon(Icons.download_rounded, color: Colors.grey.shade400, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CampCertItem {
  final bool isDonation;
  final String campTitle;
  final String organizerName;
  final DateTime date;

  _CampCertItem({
    required this.isDonation,
    required this.campTitle,
    required this.organizerName,
    required this.date,
  });

  // donations/{id} where source == 'camp'. 'date' is stored as an ISO
  // 'yyyy-MM-dd' string (same format the manual Log Donation entries use).
  factory _CampCertItem.fromDonation(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(d['date'] as String);
    } catch (_) {
      parsedDate = (d['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    }
    return _CampCertItem(
      isDonation: true,
      campTitle: (d['camp_title'] ?? 'Blood Camp').toString(),
      organizerName: (d['organizer_name'] ?? 'BloodLink').toString(),
      date: parsedDate,
    );
  }

  // camp_participations/{id}. 'date' is a Firestore Timestamp.
  factory _CampCertItem.fromParticipation(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _CampCertItem(
      isDonation: false,
      campTitle: (d['camp_title'] ?? 'Blood Camp').toString(),
      organizerName: (d['organizer_name'] ?? 'BloodLink').toString(),
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
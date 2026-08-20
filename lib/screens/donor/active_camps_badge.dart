import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Wraps any icon/card with a live top-right badge showing how many active,
/// upcoming blood camps exist. Drop this around the "Blood Camps" quick
/// action in donor_home_tab.dart:
///
///   ActiveCampsBadge(child: yourExistingCampsIconOrCard)
///
/// Reuses the exact same query as DonorBloodCampsScreen's list, so it needs
/// no new Firestore index — the status+date composite index you already
/// created covers this too.
class ActiveCampsBadge extends StatelessWidget {
  final Widget child;
  const ActiveCampsBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('blood_camps')
          .where('status', isEqualTo: 'active')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (count > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
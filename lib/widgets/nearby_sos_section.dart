import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/geo_utils.dart';

/// Drop this into any role's home tab:
///   NearbySosSection(color: color, role: 'donor', userData: widget.donorData)
///
/// role: 'donor' | 'hospital' | 'blood_bank' | 'recipient'
/// - 'donor' gets the "Help" button (accept flow).
/// - everyone else gets a "View" button (details sheet, no accept action —
///   only donors donate; Hospital/Blood Bank coordination is a later phase).
/// - the request owner (any role) sees a "Mark Fulfilled" action instead.
class NearbySosSection extends StatefulWidget {
  final Color color;
  final String role;
  final Map<String, dynamic>? userData;
  final double radiusKm;

  const NearbySosSection({
    super.key,
    required this.color,
    required this.role,
    required this.userData,
    this.radiusKm = 50,
  });

  @override
  State<NearbySosSection> createState() => _NearbySosSectionState();
}

class _NearbySosSectionState extends State<NearbySosSection> {
  ({double lat, double lng})? _viewerPoint;
  bool _locating = true;
  final Set<String> _accepting = {}; // request ids currently mid-transaction, to disable double-tap

  @override
  void initState() {
    super.initState();
    _resolveViewerLocation();
  }

  Future<void> _resolveViewerLocation() async {
    final data = widget.userData;

    // NOTE: we deliberately don't use last_lat/last_lng here even for
    // donors. On desktop (no real GPS), that field falls back to an
    // IP-based location which can be 50-100km off the registered city —
    // and worse, identical across different users testing on the same
    // network. Geocoding the registered city instead is consistent
    // across every device and matches how SOS points are computed,
    // so "same city" reliably shows up as "nearby" during testing.
    final city = (data?['city'] ?? '').toString();
    final district = (data?['district'] ?? '').toString();
    final state = (data?['state'] ?? '').toString();
    if (city.isEmpty) {
      setState(() => _locating = false);
      return;
    }
    final point = await GeoUtils.geocode('$city, $district, $state');
    if (!mounted) return;
    setState(() {
      _viewerPoint = point;
      _locating = false;
    });
  }

  Future<void> _helpSos(String requestId, Map<String, dynamic> requestData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _accepting.add(requestId));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final myName = widget.userData?['name'] ?? 'A donor';

    try {
      // Transaction guarantees only the first tap wins — reads accepted_by
      // and writes in one atomic step, so two donors tapping "Help" at the
      // same instant can't both succeed.
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        final data = snap.data() as Map<String, dynamic>;
        if (data['accepted_by'] != null) throw 'taken';
        tx.update(docRef, {
          'accepted_by': uid,
          'accepted_by_name': myName,
          'accepted_at': FieldValue.serverTimestamp(),
        });
      });

      // Best-effort notification — matches the notifications/{uid}/items schema.
      // If your NotificationService has a different send() signature, swap
      // this block for a call to it instead.
      final requesterUid = requestData['requester_uid'];
      if (requesterUid != null) {
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(requesterUid)
            .collection('items')
            .add({
          'type': 'sos_accepted',
          'title': 'Someone is helping! 🩸',
          'message': '$myName accepted your SOS request for ${requestData['blood_group'] ?? ''}.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("You're helping! The requester has been notified."),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('taken')
            ? 'Someone already accepted this request'
            : 'Could not accept — please try again';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _accepting.remove(requestId));
    }
  }

  Future<void> _deactivateSos(String requestId) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as fulfilled?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This SOS request will no longer show up for others.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection('sos_requests').doc(requestId)
          .update({'status': 'fulfilled'});
    } catch (_) {}
  }

  void _showDetailsSheet(Map<String, dynamic> d, double distance) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d['patient_name'] ?? 'Patient', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${distance.toStringAsFixed(1)} km away • ${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 14),
          if ((d['hospital'] ?? '').toString().isNotEmpty) _detailRow(Icons.local_hospital_outlined, 'Hospital', d['hospital']),
          if ((d['address'] ?? '').toString().isNotEmpty) _detailRow(Icons.location_on_outlined, 'Address', d['address']),
          _detailRow(Icons.location_city_outlined, 'City', '${d['city'] ?? ''}, ${d['district'] ?? ''}'),
          if ((d['phone'] ?? '').toString().isNotEmpty) _detailRow(Icons.phone_outlined, 'Phone', d['phone']),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.grey.shade500),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    if (_locating) return _statusBox(color, 'Finding your location…', loading: true);
    if (_viewerPoint == null) return _statusBox(color, 'Set your city in profile to see nearby SOS requests');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_requests')
          .where('status', isEqualTo: 'active').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusBox(color, 'Could not load SOS requests.\n${snapshot.error}', isError: true);
        }
        if (!snapshot.hasData) return _statusBox(color, 'Loading nearby SOS…', loading: true);

        final now = DateTime.now();
        final items = <_SosItem>[];

        for (final doc in snapshot.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;

          // Opportunistic auto-expire — no Cloud Functions on Spark plan,
          // so whichever client happens to load this first past its expiry
          // flips it to 'expired'. Fire-and-forget; failure just means the
          // next viewer's client tries again.
          final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();
          if (expiresAt != null && expiresAt.isBefore(now)) {
            doc.reference.update({'status': 'expired'}).catchError((_) {});
            continue;
          }

          final lat = d['lat'];
          final lng = d['lng'];
          if (lat is! num || lng is! num) continue; // pre-fix requests without coords — can't place on radius
          final distance = GeoUtils.distanceKm(_viewerPoint!.lat, _viewerPoint!.lng, lat.toDouble(), lng.toDouble());
          if (distance <= widget.radiusKm) items.add(_SosItem(doc.id, d, distance));
        }

        items.sort((a, b) => a.distance.compareTo(b.distance));

        if (items.isEmpty) {
          return _statusBox(color, 'No active SOS requests within ${widget.radiusKm.toInt()} km 🎉');
        }

        return Column(children: items.map((item) {
          final isMine = item.data['requester_uid'] == myUid;
          final acceptedBy = item.data['accepted_by'];
          final isAccepting = _accepting.contains(item.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Text(item.data['blood_group'] ?? '?',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.data['patient_name'] ?? 'Patient',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${item.distance.toStringAsFixed(1)} km away • ${item.data['units'] ?? 1} unit needed',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ])),
              const SizedBox(width: 8),
              if (isMine)
                GestureDetector(
                  onTap: () => _deactivateSos(item.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(acceptedBy != null ? 'Accepted • Mark done' : 'Active • Mark done',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                )
              else if (widget.role == 'donor')
                acceptedBy != null
                    ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: Text('Accepted', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600)))
                    : ElevatedButton(
                    onPressed: isAccepting ? null : () => _helpSos(item.id, item.data),
                    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: isAccepting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Help', style: TextStyle(fontSize: 12)))
              else
                OutlinedButton(
                  onPressed: () => _showDetailsSheet(item.data, item.distance),
                  style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('View', style: TextStyle(fontSize: 12)),
                ),
            ]),
          );
        }).toList());
      },
    );
  }

  Widget _statusBox(Color color, String message, {bool loading = false, bool isError = false}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        if (loading)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: color, strokeWidth: 2))
        else
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.red.shade400 : Colors.green.shade400, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(message,
            style: TextStyle(color: isError ? Colors.red.shade700 : Colors.grey.shade500, fontSize: 13))),
      ]),
    );
  }
}

class _SosItem {
  final String id;
  final Map<String, dynamic> data;
  final double distance;
  _SosItem(this.id, this.data, this.distance);
}

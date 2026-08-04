import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/geo_utils.dart';
import '../utils/blood_compatibility.dart';

/// Drop this into any role's home tab:
///   NearbySosSection(color: color, role: 'donor', userData: widget.donorData)
///
/// role: 'donor' | 'hospital' | 'blood_bank' | 'recipient'
/// - 'donor' gets the "Help" button (accept flow).
/// - everyone else gets a "View" button (details sheet, no accept action —
///   only donors donate; Hospital/Blood Bank coordination is a later phase).
/// - the request owner (any role) sees a "Mark Fulfilled" action instead.
///
/// MULTI-DONOR MODEL:
/// A request needs `units` donors (default 1). Each donor who accepts gets
/// their own doc in the `sos_requests/{id}/acceptances/{donorUid}`
/// subcollection instead of a single `accepted_by` field on the parent —
/// so more than one donor can help the same request. `units_fulfilled` on
/// the parent doc mirrors the acceptance count (kept in sync inside the
/// same transaction) purely so list queries / cards don't need to read the
/// subcollection just to know "is this full yet". Status auto-flips to
/// 'fulfilled' once units_fulfilled >= units, and reopens to 'active' if a
/// donor cancels and drops it back below that.
class NearbySosSection extends StatefulWidget {
  final Color color;
  final String role;
  final Map<String, dynamic>? userData;
  final double radiusKm;
  // When true: only shows the current user's own active SOS requests
  // (with the donor-list + "Mark done" actions), and skips the
  // location/radius lookup entirely since it isn't needed. Use this for
  // roles that create SOS requests but never accept/help others' —
  // e.g. Recipient — so they still get full status on their own request
  // without seeing (or being shown as able to act on) anyone else's.
  final bool onlyMine;
  // When false, this role's own posted SOS requests are excluded entirely
  // from this widget (still shown in "others"-style nearby list only if
  // they belong to someone else). Set false for roles that already have a
  // dedicated screen for managing their own requests (e.g. Hospital's
  // Requests tab) — avoids the same request being manageable from two
  // different screens with two different action sets.
  final bool showOwnRequests;

  const NearbySosSection({
    super.key,
    required this.color,
    required this.role,
    required this.userData,
    this.radiusKm = 50,
    this.onlyMine = false,
    this.showOwnRequests = true,
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
    if (widget.onlyMine) {
      // No radius/distance math needed for "my own requests" mode.
      _locating = false;
    } else {
      _resolveViewerLocation();
    }
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

  Future<void> _callPhone(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open dialer for $phone'),
          backgroundColor: Colors.red.shade600,
        ));
      }
    }
  }

  void _shareSos(Map<String, dynamic> d) {
    HapticFeedback.lightImpact();
    final text = '🩸 Blood needed urgently!\n'
        '${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit(s)\n'
        'Patient: ${d['patient_name'] ?? ''}\n'
        'Hospital: ${d['hospital'] ?? ''}\n'
        'Location: ${d['city'] ?? ''}, ${d['district'] ?? ''}\n'
        'Contact: ${d['phone'] ?? ''}\n\n'
        'Please help or share — via BloodLink';
    SharePlus.instance.share(ShareParams(text: text));
  }

  static int _asInt(dynamic v, {int fallback = 1}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  /// Accept flow — now writes to the acceptances subcollection instead of
  /// a single accepted_by field, so multiple donors can help one request.
  /// Transaction guarantees: re-reads units_fulfilled fresh, checks this
  /// donor hasn't already accepted, checks there's still a slot open, then
  /// creates the acceptance doc + bumps units_fulfilled (+ flips status to
  /// 'fulfilled' if that was the last slot) — all atomically. Two donors
  /// tapping "Help" on the last open slot at the same instant can't both
  /// succeed; whichever transaction commits first wins, the other retries
  /// and sees the slot is gone.
  Future<void> _helpSos(String requestId, Map<String, dynamic> requestData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _accepting.add(requestId));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final acceptanceRef = docRef.collection('acceptances').doc(uid);
    final myName = widget.userData?['name'] ?? 'A donor';
    final myPhone = widget.userData?['phone'] ?? '';

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        final data = snap.data() as Map<String, dynamic>;

        final alreadyMine = await tx.get(acceptanceRef);
        if (alreadyMine.exists) throw 'already';

        final unitsNeeded = _asInt(data['units']);
        final unitsFulfilled = _asInt(data['units_fulfilled'], fallback: 0);
        if (unitsFulfilled >= unitsNeeded) throw 'full';

        final newFulfilled = unitsFulfilled + 1;
        tx.set(acceptanceRef, {
          'donor_name': myName,
          'donor_phone': myPhone,
          'accepted_at': FieldValue.serverTimestamp(),
        });
        tx.update(docRef, {
          'units_fulfilled': newFulfilled,
          if (newFulfilled >= unitsNeeded) 'status': 'fulfilled',
        });
      }).timeout(const Duration(seconds: 10));

      // Best-effort notification — matches the notifications/{uid}/items schema.
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
      // ignore: avoid_print
      print('SOS accept error: $e');
      if (mounted) {
        String msg;
        if (e.toString().contains('already')) {
          msg = "You've already accepted this request";
        } else if (e.toString().contains('full')) {
          msg = 'All units for this request are already covered';
        } else if (e is TimeoutException) {
          msg = 'Timed out — check Firestore rules allow this update';
        } else if (e.toString().contains('permission-denied')) {
          msg = 'Permission denied — check Firestore rules for acceptances';
        } else {
          msg = 'Could not accept: $e';
        }
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

  void _showHelpConfirmation(String requestId, Map<String, dynamic> d) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Confirm you can help', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.color)),
          const SizedBox(height: 4),
          Text('Your contact will be shared with the requester so they can reach you.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 14),
          _detailRow(Icons.person_outline, 'Patient', d['patient_name'] ?? ''),
          _detailRow(Icons.bloodtype_outlined, 'Blood group / units', '${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit(s)'),
          if ((d['hospital'] ?? '').toString().isNotEmpty) _detailRow(Icons.local_hospital_outlined, 'Hospital', d['hospital']),
          _detailRow(Icons.location_city_outlined, 'City', '${d['city'] ?? ''}, ${d['district'] ?? ''}'),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _helpSos(requestId, d); },
              style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text("Yes, I'll help"),
            )),
          ]),
        ]),
      ),
    );
  }

  /// Cancel flow — removes THIS donor's acceptance doc only (other donors
  /// on the same request are untouched), decrements units_fulfilled, and
  /// reopens the request to 'active' if it had been marked 'fulfilled'.
  Future<void> _cancelHelp(String requestId) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Can't make it?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will free up your slot for other donors, and the requester will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Stay committed', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Cancel my help')),
        ],
      ),
    );
    if (confirm != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final acceptanceRef = docRef.collection('acceptances').doc(uid);

    try {
      String? requesterUid;
      String bloodGroup = '';
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>;
        requesterUid = data['requester_uid'];
        bloodGroup = (data['blood_group'] ?? '').toString();
        final unitsFulfilled = _asInt(data['units_fulfilled'], fallback: 0);
        final newFulfilled = (unitsFulfilled - 1) < 0 ? 0 : unitsFulfilled - 1;
        tx.delete(acceptanceRef);
        tx.update(docRef, {
          'units_fulfilled': newFulfilled,
          'status': 'active', // always reopens — a cancellation means a slot is free again
        });
      });

      if (requesterUid != null) {
        FirebaseFirestore.instance.collection('notifications').doc(requesterUid).collection('items').add({
          'type': 'sos_cancelled',
          'title': 'Donor unavailable 😔',
          'message': 'A donor had to back out of your $bloodGroup request. A slot is open again.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }
    } catch (_) {}
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
          const SizedBox(height: 16),
          Row(children: [
            if ((d['phone'] ?? '').toString().isNotEmpty)
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _callPhone(d['phone']),
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Call'),
                style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
            if ((d['phone'] ?? '').toString().isNotEmpty) const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _shareSos(d),
              icon: const Icon(Icons.share_outlined, size: 16),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(foregroundColor: widget.color, side: BorderSide(color: widget.color),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )),
          ]),
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

    if (widget.onlyMine) return _buildOnlyMine(color, myUid);

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

        final mine = items.where((i) => i.data['requester_uid'] == myUid).toList();
        final others = items.where((i) => i.data['requester_uid'] != myUid).toList();

        if (items.isEmpty) {
          return _statusBox(color, 'No active SOS requests within ${widget.radiusKm.toInt()} km 🎉');
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.showOwnRequests && mine.isNotEmpty) ...[
            Text('Your Active SOS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ...mine.map((item) => _buildSosCard(item, isMine: true, myUid: myUid, color: color)),
            if (others.isNotEmpty) const SizedBox(height: 16),
          ],
          if (others.isNotEmpty) ...[
            if (widget.showOwnRequests && mine.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Nearby Requests You Can Help', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700))),
            ...others.map((item) => _buildSosCard(item, isMine: false, myUid: myUid, color: color)),
          ],
        ]);
      },
    );
  }

  // "My requests only" mode — no radius/distance needed, so we query
  // directly by requester_uid instead of pulling every active SOS and
  // filtering client-side. Reuses the same card (isMine: true) so the
  // donor-list / Mark-done actions behave identically to the Donor tab.
  Widget _buildOnlyMine(Color color, String? myUid) {
    if (myUid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_requests')
          .where('requester_uid', isEqualTo: myUid)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _statusBox(color, 'Could not load your SOS requests.\n${snapshot.error}', isError: true);
        }
        if (!snapshot.hasData) return _statusBox(color, 'Loading your SOS requests…', loading: true);
        if (snapshot.data!.docs.isEmpty) {
          return _statusBox(color, 'No active SOS requests');
        }

        final items = snapshot.data!.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return _SosItem(doc.id, d, 0); // distance unused when isMine: true
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((item) => _buildSosCard(item, isMine: true, myUid: myUid, color: color)).toList(),
        );
      },
    );
  }

  /// Wraps the card in a StreamBuilder on the acceptances subcollection so
  /// it always reflects the live donor list / fulfilled count, without the
  /// parent card widget needing to know about it.
  Widget _buildSosCard(_SosItem item, {required bool isMine, required String? myUid, required Color color}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(item.id)
          .collection('acceptances')
          .orderBy('accepted_at')
          .snapshots(),
      builder: (context, accSnap) {
        final acceptanceDocs = accSnap.data?.docs ?? const [];
        final unitsNeeded = _asInt(item.data['units']);
        final unitsFulfilled = acceptanceDocs.length;
        final isFull = unitsFulfilled >= unitsNeeded;
        final iAmHelping = myUid != null && acceptanceDocs.any((d) => d.id == myUid);
        final isAccepting = _accepting.contains(item.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
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
                // Distance to yourself is meaningless — only show it for other
                // people's requests, not your own. Progress replaces the old
                // "N unit needed" text with a live "X/Y donors found" count.
                Text(isMine
                    ? '$unitsFulfilled/$unitsNeeded donors found'
                    : '${item.distance.toStringAsFixed(1)} km away • $unitsFulfilled/$unitsNeeded donors found',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ])),
              const SizedBox(width: 8),
              if (isMine)
                GestureDetector(
                  onTap: () => _deactivateSos(item.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(unitsFulfilled > 0 ? 'Mark done' : 'Active • Mark done',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                )
              else if (widget.role == 'donor')
                iAmHelping
                    ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text("You're helping", style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () => _callPhone(item.data['phone'] ?? ''),
                      child: Icon(Icons.call, size: 16, color: color),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _cancelHelp(item.id),
                      child: Text('Cancel', style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ])
                    : isFull
                    ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: Text('Fulfilled ✅', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600)))
                    : BloodCompatibility.canDonate(
                  (widget.userData?['blood_group'] ?? '').toString(),
                  (item.data['blood_group'] ?? '').toString(),
                )
                    ? ElevatedButton(
                    onPressed: isAccepting ? null : () => _showHelpConfirmation(item.id, item.data),
                    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                        disabledBackgroundColor: color.withValues(alpha: 0.6), disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: isAccepting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Help', style: TextStyle(fontSize: 12)))
                // Blood group isn't compatible — this donor can't safely give
                // blood for this request, but can still spread the word.
                    : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Not a match', style: TextStyle(color: Colors.grey.shade400, fontSize: 9, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: () => _showDetailsSheet(item.data, item.distance),
                    style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('Notify', style: TextStyle(fontSize: 12)),
                  ),
                ])
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
            // Donor list — only the requester (isMine) needs to see who's
            // coming and be able to call them. Others just see the count above.
            if (isMine && acceptanceDocs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...acceptanceDocs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green.shade400),
                    const SizedBox(width: 6),
                    Expanded(child: Text(d['donor_name'] ?? 'Donor',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                    GestureDetector(
                      onTap: () => _callPhone(d['donor_phone'] ?? ''),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.call, size: 12, color: color),
                        const SizedBox(width: 3),
                        Text('Call', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                );
              }),
            ],
          ]),
        );
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
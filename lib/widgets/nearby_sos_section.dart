import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
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

  Future<void> _messageDonor(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    final uri = Uri(scheme: 'sms', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open Messages for $phone'),
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

  /// Offer flow (Stage 1 of 2) — donor taps "I'll Help" and this creates a
  /// PENDING offer doc in the acceptances subcollection. It does NOT touch
  /// units_fulfilled and does NOT flip the request to 'fulfilled' — that
  /// only happens once the requester explicitly Accepts this donor (see
  /// _acceptDonorOffer below). This lets the requester review the donor's
  /// profile / call / message them before committing a slot to them.
  ///
  /// A snapshot of the donor's profile (name, phone, blood group, age,
  /// city/district) is stored directly on the offer doc so the requester's
  /// review UI doesn't need an extra Firestore read per offer.
  Future<void> _helpSos(String requestId, Map<String, dynamic> requestData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _accepting.add(requestId));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final acceptanceRef = docRef.collection('acceptances').doc(uid);
    final myName = widget.userData?['name'] ?? 'A donor';
    final myPhone = widget.userData?['phone'] ?? '';
    final myBloodGroup = widget.userData?['blood_group'] ?? '';
    final myAge = widget.userData?['age'];
    final myCity = widget.userData?['city'] ?? '';
    final myDistrict = widget.userData?['district'] ?? '';

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        final data = snap.data() as Map<String, dynamic>;

        final alreadyMine = await tx.get(acceptanceRef);
        if (alreadyMine.exists) throw 'already';

        // Full check is still based on ACCEPTED slots only (units_fulfilled
        // only ever counts accepted offers now) — a request can keep
        // receiving offers to review even while other offers are pending.
        final unitsNeeded = _asInt(data['units']);
        final unitsFulfilled = _asInt(data['units_fulfilled'], fallback: 0);
        if (unitsFulfilled >= unitsNeeded) throw 'full';

        tx.set(acceptanceRef, {
          'donor_name': myName,
          'donor_phone': myPhone,
          'donor_blood_group': myBloodGroup,
          'donor_age': myAge,
          'donor_city': myCity,
          'donor_district': myDistrict,
          'status': 'pending',
          'offered_at': FieldValue.serverTimestamp(),
          'accepted_at': null,
          'donation_doc_id': null,
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
          'type': 'sos_offer',
          'title': 'A donor wants to help! 🙋',
          'body': '$myName offered to help your ${requestData['blood_group'] ?? ''} request. Review their profile to confirm.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Offer sent! The requester will review and confirm."),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      // ignore: avoid_print
      print('SOS offer error: $e');
      if (mounted) {
        String msg;
        if (e.toString().contains('already')) {
          msg = "You've already offered to help this request";
        } else if (e.toString().contains('full')) {
          msg = 'All units for this request are already covered';
        } else if (e is TimeoutException) {
          msg = 'Timed out — check Firestore rules allow this update';
        } else if (e.toString().contains('permission-denied')) {
          msg = 'Permission denied — check Firestore rules for acceptances';
        } else {
          msg = 'Could not send offer: $e';
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

  /// Accept flow (Stage 2 of 2) — the REQUESTER calls this after reviewing a
  /// pending offer. Atomically: re-checks a slot is still open, flips the
  /// offer to 'accepted', bumps units_fulfilled (+ flips the request to
  /// 'fulfilled' if that was the last slot). After the transaction commits,
  /// also (a) writes a verified donation record for the donor so their
  /// History tab / badges update automatically, and (b) notifies the donor.
  Future<void> _acceptDonorOffer(String requestId, String donorUid, Map<String, dynamic> requestData) async {
    HapticFeedback.mediumImpact();
    setState(() => _accepting.add('$requestId-$donorUid'));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final offerRef = docRef.collection('acceptances').doc(donorUid);
    final donationRef = FirebaseFirestore.instance.collection('donors').doc(donorUid).collection('donations').doc();

    try {
      Map<String, dynamic>? offerData;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        final data = snap.data() as Map<String, dynamic>;

        final offerSnap = await tx.get(offerRef);
        if (!offerSnap.exists) throw 'gone';
        offerData = offerSnap.data() as Map<String, dynamic>;
        if (offerData!['status'] == 'accepted') throw 'already';

        final unitsNeeded = _asInt(data['units']);
        final unitsFulfilled = _asInt(data['units_fulfilled'], fallback: 0);
        if (unitsFulfilled >= unitsNeeded) throw 'full';

        final newFulfilled = unitsFulfilled + 1;
        tx.update(offerRef, {
          'status': 'accepted',
          'accepted_at': FieldValue.serverTimestamp(),
          'donation_doc_id': donationRef.id,
        });
        tx.update(docRef, {
          'units_fulfilled': newFulfilled,
          if (newFulfilled >= unitsNeeded) 'status': 'fulfilled',
        });
        tx.set(donationRef, {
          'type': 'Whole Blood',
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'date_display': DateFormat('dd MMM yyyy').format(DateTime.now()),
          'location': '${requestData['hospital'] ?? requestData['city'] ?? ''}'
              '${(requestData['district'] ?? '').toString().isNotEmpty ? ', ${requestData['district']}' : ''}',
          'units': 1,
          'source': 'sos',
          'verified': true,
          'request_id': requestId,
          'created_at': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 10));

      final donorName = offerData?['donor_name'] ?? 'The donor';
      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_help_accepted',
        'title': 'Your help is accepted! 🎉',
        'body': 'Thank you! Your donation for the ${requestData['blood_group'] ?? ''} request has been confirmed.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$donorName confirmed! They have been notified.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        String msg;
        if (e.toString().contains('already')) {
          msg = 'This offer is already confirmed';
        } else if (e.toString().contains('full')) {
          msg = 'All units for this request are already covered';
        } else if (e is TimeoutException) {
          msg = 'Timed out — check Firestore rules allow this update';
        } else {
          msg = 'Could not confirm this donor: $e';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _accepting.remove('$requestId-$donorUid'));
    }
  }

  /// Decline flow — REQUESTER rejects a pending offer without accepting it.
  /// Only valid while the offer is still 'pending' (an already-accepted
  /// donor is removed via the donor's own Cancel action instead, since by
  /// then they've committed a slot). Just deletes the offer doc and lets
  /// the donor know, so they can look elsewhere.
  Future<void> _declineDonorOffer(String requestId, String donorUid, Map<String, dynamic> offerData, Map<String, dynamic> requestData) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline this offer?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('${offerData['donor_name'] ?? 'This donor'} will be notified so they can help someone else.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Decline')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('sos_requests').doc(requestId)
          .collection('acceptances').doc(donorUid).delete();

      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_declined',
        'title': 'Offer declined',
        'body': 'Your offer to help the ${requestData['blood_group'] ?? ''} request wasn\'t needed this time. Thanks for stepping up!',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    } catch (_) {}
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

  /// Cancel flow (donor-initiated) — removes THIS donor's offer/acceptance
  /// doc only (other donors on the same request are untouched). Behavior
  /// branches on whether the offer had been confirmed yet:
  /// - still 'pending' (requester hadn't reviewed/accepted it): just delete
  ///   it — no units_fulfilled or donation to undo.
  /// - 'accepted': decrements units_fulfilled, reopens the request to
  ///   'active' if it had been marked 'fulfilled', AND deletes the
  ///   auto-added verified donation record (via the donation_doc_id stored
  ///   on the offer) so History/badges don't keep credit for a donation
  ///   that's no longer happening.
  Future<void> _cancelHelp(String requestId, {required bool wasAccepted}) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(wasAccepted ? "Can't make it?" : 'Withdraw your offer?', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(wasAccepted
            ? 'This will free up your slot for other donors, remove the donation from your history, and the requester will be notified.'
            : 'The requester will no longer see your offer for this request.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Stay', style: TextStyle(color: Colors.grey.shade600))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(wasAccepted ? 'Cancel my help' : 'Withdraw offer')),
        ],
      ),
    );
    if (confirm != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(requestId);
    final acceptanceRef = docRef.collection('acceptances').doc(uid);

    try {
      if (!wasAccepted) {
        // Still pending — nothing else was ever touched, so a plain delete
        // fully undoes the offer.
        await acceptanceRef.delete();
        return;
      }

      String? requesterUid;
      String bloodGroup = '';
      String? donationDocId;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>;
        requesterUid = data['requester_uid'];
        bloodGroup = (data['blood_group'] ?? '').toString();

        final offerSnap = await tx.get(acceptanceRef);
        donationDocId = offerSnap.exists ? (offerSnap.data() as Map<String, dynamic>)['donation_doc_id'] : null;

        final unitsFulfilled = _asInt(data['units_fulfilled'], fallback: 0);
        final newFulfilled = (unitsFulfilled - 1) < 0 ? 0 : unitsFulfilled - 1;
        tx.delete(acceptanceRef);
        tx.update(docRef, {
          'units_fulfilled': newFulfilled,
          'status': 'active', // always reopens — a cancellation means a slot is free again
        });
        if (donationDocId != null) {
          tx.delete(FirebaseFirestore.instance.collection('donors').doc(uid).collection('donations').doc(donationDocId));
        }
      });

      if (requesterUid != null) {
        FirebaseFirestore.instance.collection('notifications').doc(requesterUid).collection('items').add({
          'type': 'sos_cancelled',
          'title': 'Donor unavailable 😔',
          'body': 'A donor had to back out of your $bloodGroup request. A slot is open again.',
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
          .orderBy('offered_at')
          .snapshots(),
      builder: (context, accSnap) {
        final acceptanceDocs = accSnap.data?.docs ?? const [];
        // Backward-compatible: a doc with no 'status' field is treated as
        // accepted (covers any acceptance docs created before this offer/
        // accept split). Pending offers are the ones still awaiting the
        // requester's decision.
        final acceptedDocs = acceptanceDocs.where((d) => (d.data() as Map<String, dynamic>)['status'] != 'pending').toList();
        final pendingDocs = acceptanceDocs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'pending').toList();
        final unitsNeeded = _asInt(item.data['units']);
        final unitsFulfilled = acceptedDocs.length;
        final isFull = unitsFulfilled >= unitsNeeded;
        QueryDocumentSnapshot? myOfferDoc;
        if (myUid != null) {
          for (final d in acceptanceDocs) {
            if (d.id == myUid) { myOfferDoc = d; break; }
          }
        }
        final myOfferData = myOfferDoc?.data() as Map<String, dynamic>?;
        final iAmAccepted = myOfferData != null && myOfferData['status'] != 'pending';
        final iAmPending = myOfferData != null && myOfferData['status'] == 'pending';
        final iAmHelping = iAmAccepted || iAmPending; // any state where I've already acted
        final isAvailable = widget.userData?['is_available'] == true;
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
                iAmAccepted
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
                      onTap: () => _cancelHelp(item.id, wasAccepted: true),
                      child: Text('Cancel', style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ])
                    : iAmPending
                    ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text('Offer sent ⏳', style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _cancelHelp(item.id, wasAccepted: false),
                    child: Text('Withdraw', style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ])
                    : isFull
                    ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: Text('Fulfilled ✅', style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600)))
                // Not currently available to donate — can't safely commit to
                // this request right now, but can still spread the word.
                // Same fallback treatment as an incompatible blood group.
                    : !isAvailable
                    ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Not available', style: TextStyle(color: Colors.grey.shade400, fontSize: 9, fontWeight: FontWeight.w500)),
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
                        : const Text("I'll Help", style: TextStyle(fontSize: 12)))
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
            // Pending offers — only the requester (isMine) reviews these:
            // a profile summary plus Call/Message to vet the donor, then
            // Accept (commits the slot + auto-verifies the donation) or
            // Decline (frees the donor to help someone else).
            if (isMine && pendingDocs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('Offers to review', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              ...pendingDocs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final donorUid = doc.id;
                final confirming = _accepting.contains('${item.id}-$donorUid');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['donor_name'] ?? 'Donor', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${d['donor_blood_group'] ?? ''}'
                              '${d['donor_age'] != null ? ' • ${d['donor_age']} yrs' : ''}'
                              '${(d['donor_city'] ?? '').toString().isNotEmpty ? ' • ${d['donor_city']}' : ''}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ])),
                      GestureDetector(
                        onTap: () => _callPhone(d['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.call, size: 16, color: color)),
                      ),
                      GestureDetector(
                        onTap: () => _messageDonor(d['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.sms_outlined, size: 16, color: color)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: confirming ? null : () => _declineDonorOffer(item.id, donorUid, d, item.data),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400, side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Decline', style: TextStyle(fontSize: 11)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(
                        onPressed: confirming ? null : () => _acceptDonorOffer(item.id, donorUid, item.data),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: confirming
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Accept', style: TextStyle(fontSize: 11)),
                      )),
                    ]),
                  ]),
                );
              }),
            ],
            // Confirmed helpers — donors the requester has already accepted.
            if (isMine && acceptedDocs.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...acceptedDocs.map((doc) {
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
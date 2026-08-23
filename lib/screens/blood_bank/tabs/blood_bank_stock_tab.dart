import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../bank_stock_request_sheet.dart';

class BloodBankStockTab extends StatefulWidget {
  final Map<String, dynamic>? bankData;
  final Color primaryColor;
  final VoidCallback onDataUpdated;

  const BloodBankStockTab({
    super.key,
    required this.bankData,
    required this.primaryColor,
    required this.onDataUpdated,
  });

  @override
  State<BloodBankStockTab> createState() => _BloodBankStockTabState();
}

class _BloodBankStockTabState extends State<BloodBankStockTab> {
  static const List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const int _lowStockThreshold = 5;

  bool _isSaving = false;
  late Map<String, int> _editedStock;
  final Set<String> _actingOnOffer = {}; // "$sosId-$donorUid" mid-transaction, to disable double-tap
  final Set<String> _fulfilling = {}; // stock_request doc ids mid-transaction

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _editedStock = _stockFromData();
  }

  @override
  void didUpdateWidget(covariant BloodBankStockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync local edits whenever fresh data comes in from parent (e.g. after save)
    if (oldWidget.bankData != widget.bankData) {
      _editedStock = _stockFromData();
    }
  }

  Map<String, int> _stockFromData() {
    final raw = widget.bankData?['stock'] as Map<String, dynamic>? ?? {};
    return {for (final g in _bloodGroups) g: (raw[g] ?? 0) as int};
  }

  void _adjust(String group, int delta) {
    setState(() {
      final current = _editedStock[group] ?? 0;
      _editedStock[group] = (current + delta).clamp(0, 9999);
    });
  }

  Future<void> _saveStock() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('blood_banks').doc(uid).update({
        'stock': _editedStock,
      });
      widget.onDataUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock updated successfully'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openRequestSheet(String group) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => BankStockRequestSheet(bloodGroup: group, bankData: widget.bankData, primaryColor: widget.primaryColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final totalUnits = _editedStock.values.fold<int>(0, (a, b) => a + b);

    // Switched from the old fixed-header + Expanded ListView.builder layout
    // to a single scroll view — needed room to add the Active Donor
    // Requests section below the 8 stock rows without a second scrollable.
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Stock Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          Text('$totalUnits total units', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 16),

          ..._bloodGroups.map((group) {
            final units = _editedStock[group] ?? 0;
            final isLow = units < _lowStockThreshold;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isLow ? Colors.red.shade200 : Colors.grey.shade200),
              ),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: (isLow ? Colors.red : color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(group,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isLow ? Colors.red.shade700 : color))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$units units', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                  if (isLow) Text('Low stock', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500)),
                ])),
                GestureDetector(
                  onTap: () => _openRequestSheet(group),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.campaign_rounded, size: 18, color: color),
                  ),
                ),
                _StepperButton(icon: Icons.remove, color: color, onTap: () => _adjust(group, -1)),
                const SizedBox(width: 8),
                _StepperButton(icon: Icons.add, color: color, onTap: () => _adjust(group, 1)),
              ]),
            );
          }),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveStock,
              style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                disabledBackgroundColor: color.withValues(alpha: 0.6), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('Save Stock Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 28),

          // Active Donor Requests — the 📣 icon above posts here + broadcasts
          // to donors' Nearby SOS. Accepting a donor's offer writes a
          // verified donation (source: 'blood_bank', so it earns its own
          // Blood Bank Certificate, not the Hospital one) and "Fulfilled"
          // adds however many donors actually got accepted straight onto
          // this blood bank's own stock count for that group.
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Active Donor Requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('stock_requests')
                  .where('bank_uid', isEqualTo: _uid)
                  .where('status', isEqualTo: 'active').snapshots(),
              builder: (ctx, snap) {
                final count = snap.data?.docs.length ?? 0;
                return count > 0 ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text('$count active', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                ) : const SizedBox.shrink();
              },
            ),
          ]),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('stock_requests')
                .where('bank_uid', isEqualTo: _uid)
                .where('status', isEqualTo: 'active')
                .orderBy('created_at', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: color, strokeWidth: 2));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState('No active requests', 'Tap the 📣 icon next to any blood group to ask nearby donors');
              }
              return Column(children: snapshot.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return _buildRequestCard(d, doc.id, color);
              }).toList());
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> d, String docId, Color color) {
    final String? sosId = d['sos_request_id'] as String?;
    final busy = _fulfilling.contains(docId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
              child: Center(child: Text(d['blood_group'] ?? '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['blood_group'] ?? ''} • ${d['units'] ?? 1} unit${(d['units'] ?? 1) > 1 ? 's' : ''} requested',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A1A2E))),
            Text('Broadcast to nearby donors', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ])),
          GestureDetector(
            onTap: busy || sosId == null ? null : () => _markFulfilled(docId, sosId, (d['blood_group'] ?? '').toString()),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: busy
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Fulfilled', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
          ),
        ]),
        if (sosId != null) _buildOffersSection(sosId, color),
      ]),
    );
  }

  // Donor-offer review, embedded right in the bank's own request card —
  // exact same pattern as Hospital Home tab's _buildOffersSection.
  Widget _buildOffersSection(String sosId, Color color) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .collection('acceptances').orderBy('offered_at').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final pending = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'pending').toList();
        final accepted = docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] != 'pending').toList();

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('Offers to review', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            ...pending.map((doc) {
              final od = doc.data() as Map<String, dynamic>;
              final donorUid = doc.id;
              final busy = _actingOnOffer.contains('$sosId-$donorUid');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(od['donor_name'] ?? 'Donor', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${od['donor_blood_group'] ?? ''}'
                            '${od['donor_age'] != null ? ' • ${od['donor_age']} yrs' : ''}'
                            '${(od['donor_city'] ?? '').toString().isNotEmpty ? ' • ${od['donor_city']}' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ])),
                    GestureDetector(onTap: () => _callPhone(od['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.call, size: 16, color: color))),
                    GestureDetector(onTap: () => _messageDonor(od['donor_phone'] ?? ''),
                        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.sms_outlined, size: 16, color: color))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: busy ? null : () => _declineDonorOffer(sosId, donorUid, od),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400, side: BorderSide(color: Colors.red.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Decline', style: TextStyle(fontSize: 11)),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton(
                      onPressed: busy ? null : () => _acceptDonorOffer(sosId, donorUid),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: busy
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Accept', style: TextStyle(fontSize: 11)),
                    )),
                  ]),
                ]),
              );
            }),
          ],
          if (accepted.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...accepted.map((doc) {
              final od = doc.data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade400),
                  const SizedBox(width: 6),
                  Expanded(child: Text(od['donor_name'] ?? 'Donor', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                  GestureDetector(
                    onTap: () => _callPhone(od['donor_phone'] ?? ''),
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
        ]);
      },
    );
  }

  Future<void> _callPhone(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open dialer for $phone'), backgroundColor: Colors.red.shade600));
      }
    }
  }

  Future<void> _messageDonor(String phone) async {
    if (phone.isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      await launchUrl(Uri(scheme: 'sms', path: phone));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not open Messages for $phone'), backgroundColor: Colors.red.shade600));
      }
    }
  }

  // Same two-stage offer/accept flow as Hospital Home tab: re-checks a slot
  // is still open, flips the offer to 'accepted', bumps units_fulfilled,
  // releases the donor's lock, and writes a verified donation record —
  // source: 'blood_bank' (not 'sos'), so it earns a separate Blood Bank
  // Certificate instead of the Hospital one.
  Future<void> _acceptDonorOffer(String sosId, String donorUid) async {
    HapticFeedback.mediumImpact();
    setState(() => _actingOnOffer.add('$sosId-$donorUid'));

    final docRef = FirebaseFirestore.instance.collection('sos_requests').doc(sosId);
    final offerRef = docRef.collection('acceptances').doc(donorUid);
    final donationRef = FirebaseFirestore.instance.collection('donors').doc(donorUid).collection('donations').doc();
    final donorDocRef = FirebaseFirestore.instance.collection('donors').doc(donorUid);

    try {
      Map<String, dynamic>? offerData;
      Map<String, dynamic>? requestData;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) throw 'gone';
        requestData = snap.data() as Map<String, dynamic>;

        final offerSnap = await tx.get(offerRef);
        if (!offerSnap.exists) throw 'gone';
        offerData = offerSnap.data() as Map<String, dynamic>;
        if (offerData!['status'] == 'accepted') throw 'already';

        final unitsNeeded = _asInt(requestData!['units']);
        final unitsFulfilled = _asInt(requestData!['units_fulfilled'], fallback: 0);
        if (unitsFulfilled >= unitsNeeded) throw 'full';

        tx.update(offerRef, {
          'status': 'accepted',
          'accepted_at': FieldValue.serverTimestamp(),
          'donation_doc_id': donationRef.id,
        });
        tx.update(docRef, {'units_fulfilled': unitsFulfilled + 1});
        tx.update(donorDocRef, {'active_offer_request_id': null});
        tx.set(donationRef, {
          'type': 'Whole Blood',
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'date_display': DateFormat('dd MMM yyyy').format(DateTime.now()),
          'location': '${requestData!['hospital'] ?? requestData!['city'] ?? ''}'
              '${(requestData!['district'] ?? '').toString().isNotEmpty ? ', ${requestData!['district']}' : ''}',
          'units': 1,
          'source': 'blood_bank',
          'verified': true,
          'request_id': sosId,
          'created_at': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 10));

      final donorName = offerData?['donor_name'] ?? 'The donor';
      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_help_accepted',
        'title': 'Your help is accepted! 🎉',
        'body': 'Thank you! Your donation for the ${requestData?['blood_group'] ?? ''} request has been confirmed.',
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
      if (mounted) setState(() => _actingOnOffer.remove('$sosId-$donorUid'));
    }
  }

  Future<void> _declineDonorOffer(String sosId, String donorUid, Map<String, dynamic> offerData) async {
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
      final offerRef = FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .collection('acceptances').doc(donorUid);
      final donorDocRef = FirebaseFirestore.instance.collection('donors').doc(donorUid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final donorSnap = await tx.get(donorDocRef);
        String? currentActiveId;
        if (donorSnap.exists) {
          currentActiveId = donorSnap.data()?['active_offer_request_id'] as String?;
        }
        tx.delete(offerRef);
        if (currentActiveId == sosId) {
          tx.update(donorDocRef, {'active_offer_request_id': null});
        }
      });

      final requestSnap = await FirebaseFirestore.instance.collection('sos_requests').doc(sosId).get();
      final bloodGroup = (requestSnap.data()?['blood_group'] ?? '').toString();
      FirebaseFirestore.instance.collection('notifications').doc(donorUid).collection('items').add({
        'type': 'sos_declined',
        'title': 'Offer declined',
        'body': 'Your offer to help the $bloodGroup request wasn\'t needed this time. Thanks for stepping up!',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    } catch (_) {}
  }

  static int _asInt(dynamic v, {int fallback = 1}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? fallback;
  }

  // Closes the stock request AND — per Sowmi's requirement — adds however
  // many donors actually got accepted straight onto this blood bank's own
  // stock count for that group (a transaction-safe FieldValue.increment on
  // the nested stock.<group> field), so Stock Management reflects the real
  // outcome without a separate manual step.
  Future<void> _markFulfilled(String docId, String sosId, String bloodGroup) async {
    if (!_bloodGroups.contains(bloodGroup)) return;
    HapticFeedback.mediumImpact();
    setState(() => _fulfilling.add(docId));
    try {
      final acceptedSnap = await FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .collection('acceptances').where('status', isEqualTo: 'accepted').get();
      final acceptedCount = acceptedSnap.docs.length;

      if (acceptedCount > 0) {
        await FirebaseFirestore.instance.collection('blood_banks').doc(_uid)
            .update({'stock.$bloodGroup': FieldValue.increment(acceptedCount)});
      }

      await FirebaseFirestore.instance.collection('stock_requests').doc(docId)
          .update({'status': 'fulfilled', 'fulfilled_at': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance.collection('sos_requests').doc(sosId)
          .update({'status': 'fulfilled'}).catchError((_) {});

      widget.onDataUpdated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(acceptedCount > 0
              ? '$acceptedCount unit${acceptedCount > 1 ? 's' : ''} added to $bloodGroup stock'
              : 'Request closed'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not close request: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _fulfilling.remove(docId));
    }
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(Icons.inbox_rounded, size: 40, color: Colors.grey.shade200),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.w500)),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
      ]),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
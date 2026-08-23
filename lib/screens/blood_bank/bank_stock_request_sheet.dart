import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/geo_utils.dart';

// Posts a stock_requests doc (bank's own tracked request) plus a linked
// sos_requests doc — same schema SOSBottomSheet writes, so this shows up
// in every nearby donor's "Nearby SOS Requests" exactly like a normal SOS,
// just with the blood bank's own name/phone standing in for hospital/phone.
class BankStockRequestSheet extends StatefulWidget {
  final String bloodGroup;
  final Map<String, dynamic>? bankData;
  final Color primaryColor;
  const BankStockRequestSheet({super.key, required this.bloodGroup, required this.bankData, required this.primaryColor});

  @override
  State<BankStockRequestSheet> createState() => _BankStockRequestSheetState();
}

class _BankStockRequestSheetState extends State<BankStockRequestSheet> {
  int _units = 2;
  bool _isSending = false;

  Future<void> _send() async {
    final data = widget.bankData;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || data == null) return;
    final city = (data['city'] ?? '').toString();
    final district = (data['district'] ?? '').toString();
    final state = (data['state'] ?? '').toString();
    if (city.isEmpty || district.isEmpty || state.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please complete your location in Profile > Edit Profile first'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSending = true);
    try {
      final bankName = (data['bank_name'] ?? 'Blood Bank').toString();
      final phone = (data['phone'] ?? '').toString();
      final point = await GeoUtils.geocode('$city, $district, $state');
      final now = DateTime.now();

      final sosRef = await FirebaseFirestore.instance.collection('sos_requests').add({
        'blood_group': widget.bloodGroup,
        'patient_name': '$bankName (Stock Refill)',
        'hospital': bankName,
        'address': '',
        'phone': phone,
        'city': city,
        'district': district,
        'state': state,
        'lat': point?.lat,
        'lng': point?.lng,
        'units': _units,
        'units_fulfilled': 0,
        'status': 'active',
        'accepted_by': null,
        'accepted_by_name': null,
        'requester_uid': uid,
        'requester_role': 'blood_bank',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 72))),
      });

      await FirebaseFirestore.instance.collection('stock_requests').add({
        'bank_uid': uid,
        'bank_name': bankName,
        'blood_group': widget.bloodGroup,
        'units': _units,
        'city': city,
        'district': district,
        'state': state,
        'status': 'active',
        'sos_request_id': sosRef.id,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request sent to nearby ${widget.bloodGroup} donors'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
              child: Center(child: Text(widget.bloodGroup,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Request Donors', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            Text('Broadcast to nearby ${widget.bloodGroup} donors', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
        ]),
        const SizedBox(height: 20),
        const Text('Units needed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        Row(children: [
          _stepBtn(Icons.remove, color, () => setState(() => _units = (_units - 1).clamp(1, 50))),
          Expanded(child: Center(child: Text('$_units',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))))),
          _stepBtn(Icons.add, color, () => setState(() => _units = (_units + 1).clamp(1, 50))),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton.icon(
            onPressed: _isSending ? null : _send,
            icon: _isSending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.campaign_rounded),
            label: Text(_isSending ? 'Sending...' : 'Send Request'),
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(width: 40, height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20)),
    );
  }
}
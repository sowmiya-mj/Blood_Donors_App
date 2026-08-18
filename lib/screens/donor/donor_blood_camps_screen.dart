import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class DonorBloodCampsScreen extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorBloodCampsScreen({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorBloodCampsScreen> createState() => _DonorBloodCampsScreenState();
}

class _DonorBloodCampsScreenState extends State<DonorBloodCampsScreen> {
  bool _showMap = false;
  final MapController _mapController = MapController();
  final Map<String, LatLng> _geocodeCache = {};

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ---------------- Contact organizer ----------------
  Future<void> _contact(String scheme, String value, {String? subject}) async {
    if (value.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Organizer contact not available')));
      }
      return;
    }
    HapticFeedback.lightImpact();
    final uri = scheme == 'mail'
        ? Uri(scheme: 'mailto', path: value, queryParameters: subject != null ? {'subject': subject} : null)
        : Uri.parse('$scheme:$value');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    }
  }

  Widget _contactRow(Map<String, dynamic> c) {
    final phone = (c['organizer_phone'] ?? '').toString();
    final email = (c['organizer_email'] ?? '').toString();
    if (phone.isEmpty && email.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        if (phone.isNotEmpty) ...[
          _contactChip(Icons.call_rounded, 'Call', () => _contact('tel', phone)),
          const SizedBox(width: 8),
          _contactChip(Icons.sms_rounded, 'Message', () => _contact('sms', phone)),
        ],
        if (email.isNotEmpty) ...[
          if (phone.isNotEmpty) const SizedBox(width: 8),
          _contactChip(Icons.email_outlined, 'Mail', () =>
              _contact('mail', email, subject: 'Regarding: ${c['title'] ?? 'Blood Camp'}')),
        ],
      ]),
    );
  }

  Widget _contactChip(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11.5)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ---------------- Time slot generation ----------------
  List<String> _timeSlots(Map<String, dynamic> c) {
    final start = (c['start_time'] ?? '').toString();
    final end = (c['end_time'] ?? '').toString();
    if (start.isEmpty || end.isEmpty) return ['Any time during the camp'];
    try {
      final fmt = DateFormat('h:mm a');
      var s = fmt.parse(start);
      final e = fmt.parse(end);
      final slots = <String>[];
      while (s.isBefore(e)) {
        final next = s.add(const Duration(hours: 1));
        final segEnd = next.isAfter(e) ? e : next;
        slots.add('${fmt.format(s)} - ${fmt.format(segEnd)}');
        s = next;
      }
      return slots.isEmpty ? ['Any time during the camp'] : slots;
    } catch (_) {
      return ['Any time during the camp'];
    }
  }

  // ---------------- Registration bottom sheet ----------------
  void _openRegisterSheet(String campId, Map<String, dynamic> camp) {
    HapticFeedback.lightImpact();
    final slots = _timeSlots(camp);
    String intent = 'donate';
    String timeSlot = slots.first;
    DateTime? lastDonationDate;
    bool onMedication = false;
    bool recentIllness = false;
    bool eligibleConfirmed = false;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(children: [
                  Expanded(child: Text('Register for ${camp['title'] ?? 'Camp'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)))),
                  IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Divider(height: 20, color: Colors.grey.shade100),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('I want to', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _intentCard('donate', 'Donate Blood', Icons.favorite_rounded, intent,
                              (v) => setSheetState(() => intent = v))),
                      const SizedBox(width: 10),
                      Expanded(child: _intentCard('volunteer', 'Volunteer / Help', Icons.volunteer_activism_rounded, intent,
                              (v) => setSheetState(() => intent = v))),
                    ]),
                    const SizedBox(height: 20),
                    const Text('Preferred Time Slot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: timeSlot,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true, fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: slots.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setSheetState(() => timeSlot = v ?? slots.first),
                    ),
                    if (intent == 'donate') ...[
                      const SizedBox(height: 20),
                      const Text('Quick Health Check', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                      const SizedBox(height: 2),
                      Text('Helps the camp team plan — final eligibility is confirmed on-site.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                              context: ctx, initialDate: lastDonationDate ?? now,
                              firstDate: DateTime(now.year - 5), lastDate: now);
                          if (picked != null) setSheetState(() => lastDonationDate = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Last donation date (if any)',
                            filled: true, fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          child: Text(
                              lastDonationDate == null ? 'Never / not sure' :
                              '${lastDonationDate!.day}/${lastDonationDate!.month}/${lastDonationDate!.year}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _toggleRow('On any medication currently?', onMedication, (v) => setSheetState(() => onMedication = v)),
                      _toggleRow('Recent illness / fever (last 2 weeks)?', recentIllness, (v) => setSheetState(() => recentIllness = v)),
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        value: eligibleConfirmed,
                        onChanged: (v) => setSheetState(() => eligibleConfirmed = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('I confirm the above is accurate to my knowledge', style: TextStyle(fontSize: 12.5)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton(
                        onPressed: submitting || (intent == 'donate' && !eligibleConfirmed) ? null : () async {
                          setSheetState(() => submitting = true);
                          await _submitRegistration(campId, camp,
                              intent: intent, timeSlot: timeSlot,
                              lastDonationDate: lastDonationDate,
                              onMedication: onMedication, recentIllness: recentIllness);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: widget.primaryColor, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: submitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Confirm Registration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _intentCard(String value, String label, IconData icon, String selected, ValueChanged<String> onTap) {
    final sel = selected == value;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(value); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: sel ? widget.primaryColor.withValues(alpha: 0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? widget.primaryColor : Colors.grey.shade200, width: sel ? 1.5 : 1),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: sel ? widget.primaryColor : Colors.grey.shade400),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? widget.primaryColor : Colors.grey.shade500)),
        ]),
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF1A1A2E)))),
        Switch(value: value, activeColor: widget.primaryColor, onChanged: onChanged),
      ]),
    );
  }

  // ---------------- Register / Unregister / Waitlist promotion ----------------
  Future<void> _submitRegistration(String campId, Map<String, dynamic> camp, {
    required String intent, required String timeSlot,
    DateTime? lastDonationDate, required bool onMedication, required bool recentIllness,
  }) async {
    final data = widget.donorData;
    String regStatus = 'confirmed';
    try {
      final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(campId);
      final regRef = campRef.collection('registrations').doc(_uid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final regSnap = await tx.get(regRef);
        if (regSnap.exists) return;
        final campSnap = await tx.get(campRef);
        final campData = campSnap.data() as Map<String, dynamic>? ?? {};
        final maxSlots = (campData['max_slots'] as num?)?.toInt() ?? 0;
        final confirmedCount = (campData['registered_count'] as num?)?.toInt() ?? 0;
        final isFull = maxSlots > 0 && confirmedCount >= maxSlots;
        regStatus = isFull ? 'waitlisted' : 'confirmed';

        tx.set(regRef, {
          'donor_name': data?['name'] ?? 'Donor',
          'donor_phone': data?['phone'] ?? '',
          'blood_group': data?['blood_group'] ?? '',
          'intent': intent,
          'time_slot': timeSlot,
          'health': intent == 'donate' ? {
            'last_donation_date': lastDonationDate != null ? Timestamp.fromDate(lastDonationDate) : null,
            'on_medication': onMedication,
            'recent_illness': recentIllness,
          } : null,
          'reg_status': regStatus,
          'outcome': 'pending',
          'certificate_issued': false,
          'registered_at': FieldValue.serverTimestamp(),
        });
        tx.update(campRef, {
          (isFull ? 'waitlist_count' : 'registered_count'): FieldValue.increment(1),
        });
      });

      if (mounted) {
        final msg = regStatus == 'waitlisted'
            ? "You're on the waitlist — we'll notify you if a slot opens up"
            : 'Registered! See you at the camp 🩸';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: regStatus == 'waitlisted' ? Colors.orange.shade600 : Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not register: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _unregister(String campId) async {
    HapticFeedback.lightImpact();
    String? removedStatus;
    try {
      final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(campId);
      final regRef = campRef.collection('registrations').doc(_uid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final regSnap = await tx.get(regRef);
        if (!regSnap.exists) return;
        final regData = regSnap.data() as Map<String, dynamic>;
        removedStatus = regData['reg_status'] ?? 'confirmed';
        tx.delete(regRef);
        tx.update(campRef, {
          (removedStatus == 'waitlisted' ? 'waitlist_count' : 'registered_count'): FieldValue.increment(-1),
        });
      });

      if (removedStatus == 'confirmed') await _promoteFromWaitlist(campId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration cancelled')));
      }
    } catch (_) {}
  }

  // Promotes the earliest waitlisted donor when a confirmed slot frees up.
  // Needs a composite index on the `registrations` subcollection (Collection
  // scope, not Collection group): reg_status ASC + registered_at ASC.
  Future<void> _promoteFromWaitlist(String campId) async {
    try {
      final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(campId);
      final q = await campRef.collection('registrations')
          .where('reg_status', isEqualTo: 'waitlisted')
          .orderBy('registered_at')
          .limit(1)
          .get();
      if (q.docs.isEmpty) return;
      final promoteRef = q.docs.first.reference;
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(promoteRef);
        if (!snap.exists || (snap.data() as Map)['reg_status'] != 'waitlisted') return;
        tx.update(promoteRef, {'reg_status': 'confirmed'});
        tx.update(campRef, {
          'registered_count': FieldValue.increment(1),
          'waitlist_count': FieldValue.increment(-1),
        });
      });
    } catch (_) {}
  }

  // ---------------- Geocoding (unchanged) ----------------
  Future<LatLng?> _geocodeLocation(String query) async {
    if (_geocodeCache.containsKey(query)) return _geocodeCache[query];
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=in&q=${Uri.encodeComponent(query)}');
      final res = await http.get(uri, headers: {'User-Agent': 'BloodLinkApp/1.0'});
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          if (lat != null && lon != null) {
            final point = LatLng(lat, lon);
            _geocodeCache[query] = point;
            return point;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: const Text('Blood Camps'),
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list_rounded : Icons.map_rounded),
            onPressed: () { HapticFeedback.lightImpact(); setState(() => _showMap = !_showMap); },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('blood_camps')
            .where('status', isEqualTo: 'active')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .orderBy('date')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: color));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.campaign_outlined, size: 50, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No upcoming blood camps right now', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Check back soon!', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                ]),
              ),
            );
          }
          return _showMap ? _buildMapView(docs, color) : _buildListView(docs, color);
        },
      ),
    );
  }

  Widget _buildListView(List<QueryDocumentSnapshot> docs, Color color) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, i) => _buildCampCard(docs[i], color),
    );
  }

  Widget _buildMapView(List<QueryDocumentSnapshot> docs, Color color) {
    return FutureBuilder<List<_MapPin>>(
      future: _buildPins(docs),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: color, strokeWidth: 2),
                const SizedBox(height: 12),
                Text('Placing camps on map…', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ]));
        }
        final pins = snap.data ?? [];
        if (pins.isEmpty) {
          return Center(child: Text('Could not locate camps on map', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)));
        }
        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: pins.first.point, initialZoom: 9),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.bloodlink.app'),
            MarkerLayer(
                markers: pins
                    .map((p) => Marker(
                  point: p.point, width: 48, height: 48,
                  child: GestureDetector(
                    onTap: () => _showCampSheet(p.doc, color),
                    child: Container(
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)]),
                      child: const Center(child: Icon(Icons.campaign_rounded, color: Colors.white, size: 20)),
                    ),
                  ),
                ))
                    .toList()),
          ],
        );
      },
    );
  }

  Future<List<_MapPin>> _buildPins(List<QueryDocumentSnapshot> docs) async {
    final pins = <_MapPin>[];
    for (final doc in docs) {
      final c = doc.data() as Map<String, dynamic>;
      final lat = (c['lat'] as num?)?.toDouble();
      final lng = (c['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        pins.add(_MapPin(point: LatLng(lat, lng), doc: doc));
        continue;
      }
      final query = [c['city'], c['district'], c['state']].where((e) => e != null && e.toString().isNotEmpty).join(', ');
      if (query.isEmpty) continue;
      final point = await _geocodeLocation(query);
      if (point != null) pins.add(_MapPin(point: point, doc: doc));
    }
    return pins;
  }

  void _showCampSheet(QueryDocumentSnapshot doc, Color color) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(padding: const EdgeInsets.all(20), child: _buildCampCard(doc, color, inSheet: true)),
    );
  }

  Widget _buildCampCard(QueryDocumentSnapshot doc, Color color, {bool inSheet = false}) {
    final c = doc.data() as Map<String, dynamic>;
    final date = (c['date'] as Timestamp?)?.toDate();
    final regCount = c['registered_count'] ?? 0;
    final waitlistCount = c['waitlist_count'] ?? 0;
    final maxSlots = (c['max_slots'] as num?)?.toInt() ?? 0;
    final location = [c['city'], c['district'], c['state']].where((e) => e != null && e.toString().isNotEmpty).join(', ');

    return Container(
      margin: inSheet ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: inSheet ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
              child: Icon(Icons.campaign_rounded, color: color, size: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['title'] ?? 'Blood Camp', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(c['organizer_name'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
        ]),
        const SizedBox(height: 12),
        if (date != null)
          _rowItem(Icons.calendar_today_rounded,
              '${date.day}/${date.month}/${date.year}${(c['start_time'] ?? '').toString().isNotEmpty ? '  •  ${c['start_time']}${(c['end_time'] ?? '').toString().isNotEmpty ? ' - ${c['end_time']}' : ''}' : ''}'),
        if (location.isNotEmpty) _rowItem(Icons.location_on_outlined, location),
        if ((c['address'] ?? '').toString().isNotEmpty) _rowItem(Icons.pin_drop_outlined, c['address']),
        if ((c['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(c['description'], style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(maxSlots > 0 ? '$regCount / $maxSlots registered' : '$regCount registered',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
          if (waitlistCount > 0)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('$waitlistCount on waitlist',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('blood_camps').doc(doc.id).collection('registrations').doc(_uid).snapshots(),
          builder: (context, regSnap) {
            final regData = regSnap.data?.data() as Map<String, dynamic>?;
            final isRegistered = regSnap.data?.exists ?? false;
            final isWaitlisted = regData?['reg_status'] == 'waitlisted';
            return SizedBox(
              width: double.infinity,
              child: isRegistered
                  ? OutlinedButton.icon(
                onPressed: () => _unregister(doc.id),
                icon: Icon(isWaitlisted ? Icons.hourglass_top_rounded : Icons.check_circle_rounded, size: 17),
                label: Text(isWaitlisted ? "On waitlist — tap to cancel" : "You're registered — tap to cancel"),
                style: OutlinedButton.styleFrom(
                    foregroundColor: isWaitlisted ? Colors.orange.shade700 : Colors.green.shade600,
                    side: BorderSide(color: isWaitlisted ? Colors.orange.shade300 : Colors.green.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )
                  : ElevatedButton.icon(
                onPressed: () => _openRegisterSheet(doc.id, c),
                icon: const Icon(Icons.how_to_reg_rounded, size: 17),
                label: const Text('Register'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            );
          },
        ),
        _contactRow(c),
      ]),
    );
  }

  Widget _rowItem(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: Colors.grey.shade400),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
    ]),
  );
}

class _MapPin {
  final LatLng point;
  final QueryDocumentSnapshot doc;
  _MapPin({required this.point, required this.doc});
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  Future<void> _register(String campId, Map<String, dynamic> camp) async {
    HapticFeedback.lightImpact();
    final data = widget.donorData;
    try {
      final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(campId);
      final regRef = campRef.collection('registrations').doc(_uid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final regSnap = await tx.get(regRef);
        if (regSnap.exists) return; // already registered, no-op
        tx.set(regRef, {
          'donor_name': data?['name'] ?? 'Donor',
          'donor_phone': data?['phone'] ?? '',
          'blood_group': data?['blood_group'] ?? '',
          'registered_at': FieldValue.serverTimestamp(),
        });
        tx.update(campRef, {'registered_count': FieldValue.increment(1)});
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Registered! See you at the camp 🩸'),
          backgroundColor: Colors.green.shade600,
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
    try {
      final campRef = FirebaseFirestore.instance.collection('blood_camps').doc(campId);
      final regRef = campRef.collection('registrations').doc(_uid);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final regSnap = await tx.get(regRef);
        if (!regSnap.exists) return;
        tx.delete(regRef);
        tx.update(campRef, {'registered_count': FieldValue.increment(-1)});
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration cancelled')));
      }
    } catch (_) {}
  }

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
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _showMap = !_showMap);
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // NOTE: equality (status) + range/orderBy (date) needs a composite
        // index. Firestore throws a failed-precondition error with a direct
        // "create index" console link the first time this runs — click it
        // once and the index builds itself in a minute or two.
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
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bloodlink.app',
            ),
            MarkerLayer(
                markers: pins
                    .map((p) => Marker(
                  point: p.point,
                  width: 48,
                  height: 48,
                  child: GestureDetector(
                    onTap: () => _showCampSheet(p.doc, color),
                    child: Container(
                      decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
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
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: _buildCampCard(doc, color, inSheet: true),
      ),
    );
  }

  Widget _buildCampCard(QueryDocumentSnapshot doc, Color color, {bool inSheet = false}) {
    final c = doc.data() as Map<String, dynamic>;
    final date = (c['date'] as Timestamp?)?.toDate();
    final regCount = c['registered_count'] ?? 0;
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
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
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
          _rowItem(
              Icons.calendar_today_rounded,
              '${date.day}/${date.month}/${date.year}${(c['start_time'] ?? '').toString().isNotEmpty ? '  •  ${c['start_time']}${(c['end_time'] ?? '').toString().isNotEmpty ? ' - ${c['end_time']}' : ''}' : ''}'),
        if (location.isNotEmpty) _rowItem(Icons.location_on_outlined, location),
        if ((c['address'] ?? '').toString().isNotEmpty) _rowItem(Icons.pin_drop_outlined, c['address']),
        if ((c['description'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(c['description'], style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$regCount registered', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('blood_camps')
              .doc(doc.id)
              .collection('registrations')
              .doc(_uid)
              .snapshots(),
          builder: (context, regSnap) {
            final isRegistered = regSnap.data?.exists ?? false;
            return SizedBox(
              width: double.infinity,
              child: isRegistered
                  ? OutlinedButton.icon(
                onPressed: () => _unregister(doc.id),
                icon: const Icon(Icons.check_circle_rounded, size: 17),
                label: const Text("You're registered — tap to cancel"),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade600,
                    side: BorderSide(color: Colors.green.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )
                  : ElevatedButton.icon(
                onPressed: () => _register(doc.id, c),
                icon: const Icon(Icons.how_to_reg_rounded, size: 17),
                label: const Text('Register'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            );
          },
        ),
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
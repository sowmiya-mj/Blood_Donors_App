import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DoctorNearbyMapTab extends StatefulWidget {
  final Map<String, dynamic>? doctorData;
  final Color primaryColor;
  const DoctorNearbyMapTab({super.key, required this.doctorData, required this.primaryColor});
  @override
  State<DoctorNearbyMapTab> createState() => _DoctorNearbyMapTabState();
}

class _DoctorNearbyMapTabState extends State<DoctorNearbyMapTab> {
  bool _isLoading = true;
  bool _isGeocoding = false;
  List<Map<String, dynamic>> _donors = [];
  List<_LocationCluster> _clusters = [];
  final Map<String, LatLng> _geocodeCache = {};
  final MapController _mapController = MapController();
  bool _showList = false;

  String get _district => widget.doctorData?['district'] ?? '';
  String get _state => widget.doctorData?['state'] ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearby());
  }

  Future<void> _loadNearby() async {
    if (_state.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() { _isLoading = true; _clusters = []; });

    try {
      Query query = FirebaseFirestore.instance
          .collection('donors')
          .where('is_available', isEqualTo: true)
          .where('state', isEqualTo: _state);

      if (_district.isNotEmpty) {
        query = query.where('district', isEqualTo: _district);
      }

      final snap = await query.limit(100).get();
      final donors = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      setState(() { _donors = donors; _isLoading = false; });
      if (donors.isNotEmpty) _geocodeDonors(donors);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // Donors with a fresh GPS fix (last_lat/last_lng from their last login) get
  // their own precise pin. Everyone else is grouped by registered city and
  // geocoded via free OpenStreetMap Nominatim.
  Future<void> _geocodeDonors(List<Map<String, dynamic>> donors) async {
    setState(() => _isGeocoding = true);

    final List<_LocationCluster> gpsClusters = [];
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final d in donors) {
      final lat = (d['last_lat'] as num?)?.toDouble();
      final lng = (d['last_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        gpsClusters.add(_LocationCluster(
          label: [d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
          point: LatLng(lat, lng),
          donors: [d],
          isLiveLocation: true,
        ));
        continue;
      }
      final key = [d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', ');
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(d);
    }

    final List<_LocationCluster> clusters = [...gpsClusters];
    for (final entry in grouped.entries) {
      LatLng? point = _geocodeCache[entry.key];
      if (point == null) {
        point = await _geocodeLocation(entry.key);
        if (point != null) _geocodeCache[entry.key] = point;
        await Future.delayed(const Duration(milliseconds: 1100));
      }
      if (point != null) clusters.add(_LocationCluster(label: entry.key, point: point, donors: entry.value));
    }

    if (!mounted) return;
    setState(() { _clusters = clusters; _isGeocoding = false; });

    if (clusters.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 200), () => _mapController.move(clusters.first.point, 10));
    }
  }

  Future<LatLng?> _geocodeLocation(String query) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=in&q=${Uri.encodeComponent(query)}');
      final res = await http.get(uri, headers: {'User-Agent': 'BloodLinkApp/1.0'});
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          if (lat != null && lon != null) return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    if (_state.isEmpty) {
      return SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_off_rounded, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Set your district/state in Profile to see nearby donors',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ]),
      )));
    }

    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nearby Donors', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 2),
              Text('${_district.isNotEmpty ? '$_district, ' : ''}$_state',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ])),
            GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); _loadNearby(); },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.refresh_rounded, color: color, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); setState(() => _showList = !_showList); },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(_showList ? Icons.map_rounded : Icons.list_rounded, color: color, size: 20),
              ),
            ),
          ]),
        ),

        if (_isLoading || _isGeocoding)
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: color, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(_isLoading ? 'Loading nearby donors…' : 'Placing on map…', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ])))
        else if (_donors.isEmpty)
          Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_off_rounded, size: 50, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No available donors nearby right now', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
            ]),
          )))
        else if (_showList)
            Expanded(child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: _donors.map((d) => _buildDonorCard(d, color)).toList(),
            ))
          else
            Expanded(child: _clusters.isEmpty
                ? Center(child: Text('Could not locate donors on map', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))
                : FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _clusters.first.point, initialZoom: 10),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bloodlink.app',
                ),
                MarkerLayer(markers: _clusters.map((c) => Marker(
                  point: c.point,
                  width: 48, height: 48,
                  child: GestureDetector(
                    onTap: () => _showClusterSheet(c, color),
                    child: Container(
                      decoration: BoxDecoration(
                          color: c.isLiveLocation ? Colors.green.shade600 : color, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)]),
                      child: Center(child: Text('${c.donors.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                    ),
                  ),
                )).toList()),
              ],
            )),
      ]),
    );
  }

  void _showClusterSheet(_LocationCluster cluster, Color color) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(cluster.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)))),
            if (cluster.isLiveLocation)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text('Live location', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text('${cluster.donors.length} donor${cluster.donors.length > 1 ? 's' : ''}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 14),
          ...cluster.donors.map((d) => _buildDonorCard(d, color)),
        ]),
      ),
    );
  }

  Widget _buildDonorCard(Map<String, dynamic> d, Color color) {
    final hasLiveLocation = d['last_lat'] != null && d['last_lng'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(width: 46, height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
            child: Center(child: Text(d['blood_group'] ?? '?',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(d['name'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
            if (hasLiveLocation) ...[
              const SizedBox(width: 6),
              Icon(Icons.my_location_rounded, size: 12, color: Colors.green.shade600),
            ],
          ]),
          const SizedBox(height: 2),
          Text([d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('Available', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _LocationCluster {
  final String label;
  final LatLng point;
  final List<Map<String, dynamic>> donors;
  final bool isLiveLocation;
  _LocationCluster({required this.label, required this.point, required this.donors, this.isLiveLocation = false});
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

enum _FacilityType { hospital, bloodBank }

// Pushed as a full-screen route (Navigator.push), NOT a bottom-nav tab —
// keeps the Donor dashboard at 4 tabs. Reached from Home tab's "Blood Bank"
// Quick Action. Shows every hospital + blood bank in India, no
// district/state filtering (unlike Doctor's Nearby Donor map, which is
// intentionally scoped to the doctor's own district/state).
class DonorHospitalsBloodBanksMapScreen extends StatefulWidget {
  final Color primaryColor;
  const DonorHospitalsBloodBanksMapScreen({super.key, required this.primaryColor});
  @override
  State<DonorHospitalsBloodBanksMapScreen> createState() => _DonorHospitalsBloodBanksMapScreenState();
}

class _DonorHospitalsBloodBanksMapScreenState extends State<DonorHospitalsBloodBanksMapScreen> {
  bool _isLoading = true;
  bool _isGeocoding = false;
  List<_Facility> _facilities = [];
  List<_LocationCluster> _clusters = [];
  final Map<String, LatLng> _geocodeCache = {};
  final MapController _mapController = MapController();
  bool _showList = false;
  String _filter = 'all'; // all / hospital / bloodBank

  static const LatLng _indiaCenter = LatLng(22.5, 79.0);
  static const double _indiaZoom = 4.3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    setState(() { _isLoading = true; _clusters = []; });
    try {
      // NOTE: assumes hospitals/blood_banks docs use the same field naming
      // as donors (name, city, district, state, phone). Adjust the keys in
      // _Facility.fromDoc below if your schema differs.
      final hospitalSnap = await FirebaseFirestore.instance.collection('hospitals').limit(300).get();
      final bankSnap = await FirebaseFirestore.instance.collection('blood_banks').limit(300).get();

      final facilities = <_Facility>[
        ...hospitalSnap.docs.map((d) => _Facility.fromDoc(d.data(), _FacilityType.hospital)),
        ...bankSnap.docs.map((d) => _Facility.fromDoc(d.data(), _FacilityType.bloodBank)),
      ];

      setState(() { _facilities = facilities; _isLoading = false; });
      if (facilities.isNotEmpty) _geocodeFacilities(facilities);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  List<_Facility> get _filtered {
    if (_filter == 'hospital') return _facilities.where((f) => f.type == _FacilityType.hospital).toList();
    if (_filter == 'bloodBank') return _facilities.where((f) => f.type == _FacilityType.bloodBank).toList();
    return _facilities;
  }

  Future<void> _geocodeFacilities(List<_Facility> facilities) async {
    setState(() => _isGeocoding = true);
    final Map<String, List<_Facility>> grouped = {};
    for (final f in facilities) {
      final key = [f.city, f.district, f.state].where((e) => e != null && e.toString().isNotEmpty).join(', ');
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(f);
    }

    final List<_LocationCluster> clusters = [];
    for (final entry in grouped.entries) {
      LatLng? point = _geocodeCache[entry.key];
      if (point == null) {
        point = await _geocodeLocation(entry.key);
        if (point != null) _geocodeCache[entry.key] = point;
        await Future.delayed(const Duration(milliseconds: 1100)); // Nominatim rate limit — 1 req/sec
      }
      if (point != null) clusters.add(_LocationCluster(label: entry.key, point: point, facilities: entry.value));
    }

    if (!mounted) return;
    setState(() { _clusters = clusters; _isGeocoding = false; });

    // Frame the whole country rather than jumping to the first cluster —
    // this is an India-wide map, not a nearby-radius one.
    Future.delayed(const Duration(milliseconds: 200), () => _mapController.move(_indiaCenter, _indiaZoom));
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

  Future<void> _callFacility(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    HapticFeedback.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  List<_LocationCluster> get _filteredClusters {
    if (_filter == 'all') return _clusters;
    final wantType = _filter == 'hospital' ? _FacilityType.hospital : _FacilityType.bloodBank;
    return _clusters
        .map((c) => _LocationCluster(
        label: c.label, point: c.point,
        facilities: c.facilities.where((f) => f.type == wantType).toList()))
        .where((c) => c.facilities.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    final clusters = _filteredClusters;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Hospitals & Blood Banks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(_showList ? Icons.map_rounded : Icons.list_rounded),
            onPressed: () { HapticFeedback.lightImpact(); setState(() => _showList = !_showList); },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () { HapticFeedback.lightImpact(); _loadAll(); },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              _buildFilterChip('all', 'All', color),
              const SizedBox(width: 8),
              _buildFilterChip('hospital', 'Hospitals', Colors.blue.shade600),
              const SizedBox(width: 8),
              _buildFilterChip('bloodBank', 'Blood Banks', Colors.red.shade600),
            ]),
          ),
          if (_isLoading || _isGeocoding)
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: color, strokeWidth: 2),
              const SizedBox(height: 12),
              Text(_isLoading ? 'Loading facilities across India…' : 'Placing on map…',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ])))
          else if (_filtered.isEmpty)
            Expanded(child: Center(child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_hospital_outlined, size: 50, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No facilities found', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              ]),
            )))
          else if (_showList)
              Expanded(child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _filtered.map((f) => _buildFacilityCard(f, color)).toList(),
              ))
            else
              Expanded(child: clusters.isEmpty
                  ? Center(child: Text('Could not place facilities on map', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))
                  : FlutterMap(
                mapController: _mapController,
                options: const MapOptions(initialCenter: _indiaCenter, initialZoom: _indiaZoom),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.bloodlink.app',
                  ),
                  MarkerLayer(markers: clusters.map((c) {
                    final hasHospital = c.facilities.any((f) => f.type == _FacilityType.hospital);
                    final hasBank = c.facilities.any((f) => f.type == _FacilityType.bloodBank);
                    final pinColor = hasHospital && hasBank
                        ? Colors.purple
                        : (hasHospital ? Colors.blue.shade600 : Colors.red.shade600);
                    return Marker(
                      point: c.point,
                      width: 46, height: 46,
                      child: GestureDetector(
                        onTap: () => _showClusterSheet(c, color),
                        child: Container(
                          decoration: BoxDecoration(
                              color: pinColor, shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)]),
                          child: Center(child: Text('${c.facilities.length}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                        ),
                      ),
                    );
                  }).toList()),
                ],
              )),
        ]),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, Color color) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); setState(() => _filter = value); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade600)),
      ),
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
          Text(cluster.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          Text('${cluster.facilities.length} facilit${cluster.facilities.length > 1 ? 'ies' : 'y'}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 14),
          ...cluster.facilities.map((f) => _buildFacilityCard(f, color)),
        ]),
      ),
    );
  }

  Widget _buildFacilityCard(_Facility f, Color color) {
    final isHospital = f.type == _FacilityType.hospital;
    final typeColor = isHospital ? Colors.blue.shade600 : Colors.red.shade600;
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(width: 46, height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: typeColor.withValues(alpha: 0.1)),
            child: Icon(isHospital ? Icons.local_hospital_rounded : Icons.bloodtype_rounded, color: typeColor, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E)))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(isHospital ? 'Hospital' : 'Blood Bank',
                    style: TextStyle(fontSize: 9, color: typeColor, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 2),
          Text([f.city, f.district, f.state].where((e) => e != null && e.toString().isNotEmpty).join(', '),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ])),
        if (f.phone != null && f.phone!.isNotEmpty)
          GestureDetector(
            onTap: () => _callFacility(f.phone),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: Icon(Icons.call_rounded, color: Colors.green.shade600, size: 18),
            ),
          ),
      ]),
    );
  }
}

class _Facility {
  final String name;
  final String? city, district, state, phone;
  final _FacilityType type;
  _Facility({required this.name, this.city, this.district, this.state, this.phone, required this.type});

  factory _Facility.fromDoc(Map<String, dynamic> data, _FacilityType type) {
    final name = type == _FacilityType.hospital ? data['hospital_name'] : data['bank_name'];
    return _Facility(
      name: name ?? (type == _FacilityType.hospital ? 'Hospital' : 'Blood Bank'),
      city: data['city'],
      district: data['district'],
      state: data['state'],
      phone: data['phone'],
      type: type,
    );
  }
}

class _LocationCluster {
  final String label;
  final LatLng point;
  final List<_Facility> facilities;
  _LocationCluster({required this.label, required this.point, required this.facilities});
}
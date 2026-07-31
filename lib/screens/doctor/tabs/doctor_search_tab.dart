import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DoctorSearchTab extends StatefulWidget {
  final Map<String, dynamic>? doctorData;
  final Color primaryColor;
  const DoctorSearchTab({super.key, required this.doctorData, required this.primaryColor});
  @override
  State<DoctorSearchTab> createState() => _DoctorSearchTabState();
}

class _DoctorSearchTabState extends State<DoctorSearchTab> with SingleTickerProviderStateMixin {
  String? _selectedBloodGroup;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _showFilters = false;
  bool _showMap = false;
  bool _isGeocoding = false;
  List<Map<String, dynamic>> _results = [];

  // Location filters from JSON
  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  String? _filterState;
  String? _filterDistrict;
  final TextEditingController _cityCtrl = TextEditingController();
  bool _loadingLocation = true;

  // Geocoded pins: "city, district, state" -> LatLng, plus which donors sit there
  final Map<String, LatLng> _geocodeCache = {};
  List<_LocationCluster> _clusters = [];
  final MapController _mapController = MapController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadLocationData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationData() async {
    try {
      final String data = await rootBundle.loadString('assets/data/india_locations.json');
      final Map<String, dynamic> json = jsonDecode(data);
      setState(() {
        _locationData = json;
        _states = json.keys.toList()..sort();
        _loadingLocation = false;
      });
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  void _onStateChanged(String? state) {
    setState(() {
      _filterState = state;
      _filterDistrict = null;
      _cityCtrl.clear();
      if (state != null) {
        final stateData = _locationData[state] as Map<String, dynamic>? ?? {};
        _districts = stateData.keys.toList()..sort();
      } else {
        _districts = [];
      }
    });
  }

  Future<void> _search() async {
    if (_selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please select a blood group'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    setState(() { _hasSearched = true; _isSearching = true; _results = []; _clusters = []; });

    try {
      Query query = FirebaseFirestore.instance
          .collection('donors')
          .where('is_available', isEqualTo: true)
          .where('blood_group', isEqualTo: _selectedBloodGroup);

      if (_filterState != null) query = query.where('state', isEqualTo: _filterState);
      if (_filterDistrict != null) query = query.where('district', isEqualTo: _filterDistrict);

      final snap = await query.limit(50).get();
      var results = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      if (_cityCtrl.text.trim().isNotEmpty) {
        final cityQuery = _cityCtrl.text.trim().toLowerCase();
        results = results.where((d) =>
            (d['city'] as String? ?? '').toLowerCase().contains(cityQuery)).toList();
      }

      setState(() => _results = results);
      if (results.isNotEmpty) _geocodeResults(results);
    } catch (_) {
    } finally {
      setState(() => _isSearching = false);
    }
  }

  // Groups donors by city/district/state, geocodes each unique location via
  // OpenStreetMap Nominatim (free, no API key), and builds map clusters.
  Future<void> _geocodeResults(List<Map<String, dynamic>> results) async {
    setState(() => _isGeocoding = true);

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final d in results) {
      final key = [d['city'], d['district'], d['state']]
          .where((e) => e != null && e.toString().isNotEmpty)
          .join(', ');
      if (key.isEmpty) continue;
      grouped.putIfAbsent(key, () => []).add(d);
    }

    final List<_LocationCluster> clusters = [];
    for (final entry in grouped.entries) {
      LatLng? point = _geocodeCache[entry.key];
      if (point == null) {
        point = await _geocodeLocation(entry.key);
        if (point != null) _geocodeCache[entry.key] = point;
        // Nominatim usage policy: max ~1 request/sec
        await Future.delayed(const Duration(milliseconds: 1100));
      }
      if (point != null) {
        clusters.add(_LocationCluster(label: entry.key, point: point, donors: entry.value));
      }
    }

    if (!mounted) return;
    setState(() { _clusters = clusters; _isGeocoding = false; });

    if (clusters.isNotEmpty && _showMap) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _mapController.move(clusters.first.point, 6.5);
      });
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

  void _clearFilters() => setState(() {
    _filterState = null;
    _filterDistrict = null;
    _districts = [];
    _cityCtrl.clear();
    _results.clear();
    _clusters.clear();
    _hasSearched = false;
  });

  bool get _hasActiveFilters =>
      _filterState != null || _filterDistrict != null || _cityCtrl.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            const Text('Find Donors',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text('Search available donors near your patients',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 16),

            // Blood group picker
            const Text('Blood Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: _bloodGroups.map((group) {
              final selected = _selectedBloodGroup == group;
              return GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedBloodGroup = group); },
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58, height: 42,
                    decoration: BoxDecoration(
                        color: selected ? color : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? color : Colors.grey.shade200, width: selected ? 2 : 1)),
                    child: Center(child: Text(group, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.grey.shade700)))),
              );
            }).toList()),

            const SizedBox(height: 16),

            // Filter toggle row
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Row(children: [
                    Icon(Icons.filter_list_rounded, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text('Location Filters', style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Icon(_showFilters ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: Colors.grey.shade600),
                  ]),
                ),
              )),
              if (_hasActiveFilters) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearFilters,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.close_rounded, size: 18, color: Colors.red.shade400),
                  ),
                ),
              ],
            ]),

            if (_showFilters) ...[
              const SizedBox(height: 12),
              _loadingLocation
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(children: [
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _filterState,
                    decoration: _filterInputDecoration(color).copyWith(hintText: 'State'),
                    items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: _onStateChanged,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _filterDistrict,
                    decoration: _filterInputDecoration(color).copyWith(hintText: 'District'),
                    items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: _filterState == null ? null : (v) => setState(() => _filterDistrict = v),
                  )),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cityCtrl,
                  decoration: _filterInputDecoration(color).copyWith(hintText: 'City (optional)', prefixIcon: const Icon(Icons.location_city_outlined, size: 18)),
                  style: const TextStyle(fontSize: 13),
                ),
              ]),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSearching ? null : _search,
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _isSearching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Search Donors', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),

            const SizedBox(height: 20),

            if (_results.isNotEmpty) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_results.length} donor${_results.length > 1 ? 's' : ''} found',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                _buildViewToggle(color),
              ]),
              const SizedBox(height: 12),
              if (_showMap) _buildMapView(color) else ..._results.map((d) => _buildDonorCard(d, color)),
            ] else if (!_isSearching && _hasSearched) ...[
              Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(children: [
                Icon(Icons.search_off_rounded, size: 55, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No donors found', style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w600)),
              ]))),
            ] else if (!_isSearching) ...[
              Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(children: [
                Icon(Icons.search_rounded, size: 50, color: Colors.grey.shade200),
                const SizedBox(height: 12),
                Text('Select a blood group and search', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
              ]))),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildViewToggle(Color color) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _viewToggleBtn(Icons.list_rounded, !_showMap, color, () => setState(() => _showMap = false)),
        _viewToggleBtn(Icons.map_rounded, _showMap, color, () => setState(() => _showMap = true)),
      ]),
    );
  }

  Widget _viewToggleBtn(IconData icon, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: active ? color : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: active ? Colors.white : Colors.grey.shade500),
      ),
    );
  }

  Widget _buildMapView(Color color) {
    if (_isGeocoding) {
      return Container(
        height: 320, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: color, strokeWidth: 2),
          const SizedBox(height: 12),
          Text('Locating donors on map…', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ]),
      );
    }

    if (_clusters.isEmpty) {
      return Container(
        height: 200, alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
        child: Text('Could not locate donors on map', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 380,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _clusters.first.point, initialZoom: 6.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bloodlink.app',
            ),
            MarkerLayer(markers: _clusters.map((c) => Marker(
              point: c.point,
              width: 46, height: 46,
              child: GestureDetector(
                onTap: () => _showClusterSheet(c, color),
                child: Container(
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)]),
                  child: Center(child: Text('${c.donors.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                ),
              ),
            )).toList()),
          ],
        ),
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
          Text('${cluster.donors.length} donor${cluster.donors.length > 1 ? 's' : ''}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 14),
          ...cluster.donors.map((d) => _buildDonorCard(d, color)),
        ]),
      ),
    );
  }

  InputDecoration _filterInputDecoration(Color color) => InputDecoration(
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
  );

  Widget _buildDonorCard(Map<String, dynamic> d, Color color) {
    final isMe = d['uid'] == FirebaseAuth.instance.currentUser?.uid;
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
            Text(isMe ? 'You' : (d['name'] ?? 'Anonymous'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
            if (isMe) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text('You', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600))),
            ],
          ]),
          const SizedBox(height: 2),
          Text([d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          if (d['age'] != null)
            Text('Age ${d['age']}', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
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
  _LocationCluster({required this.label, required this.point, required this.donors});
}

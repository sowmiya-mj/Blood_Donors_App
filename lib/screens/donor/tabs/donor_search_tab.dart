import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../common/sos/sos_bottom_sheet.dart';

class DonorSearchTab extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorSearchTab({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorSearchTab> createState() => _DonorSearchTabState();
}

class _DonorSearchTabState extends State<DonorSearchTab>
    with SingleTickerProviderStateMixin {

  // Search mode: 0=Donors, 1=Blood Banks, 2=Hospitals
  int _searchMode = 0;

  String? _selectedBloodGroup;
  bool _isSearching = false;
  bool _sosActive = false;
  bool _showFilters = false;
  List<Map<String, dynamic>> _results = [];

  // Location filters from JSON
  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];

  String? _filterState;
  String? _filterDistrict;
  final TextEditingController _cityCtrl = TextEditingController();
  bool _loadingLocation = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

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

  Future<void> _searchDonors() async {
    if (_searchMode == 0 && _selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please select a blood group'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    setState(() { _isSearching = true; _results = []; });

    try {
      if (_searchMode == 0) {
        // Search donors — case insensitive via Firestore range query
        Query query = FirebaseFirestore.instance
            .collection('donors')
            .where('is_available', isEqualTo: true);

        if (_selectedBloodGroup != null) {
          query = query.where('blood_group', isEqualTo: _selectedBloodGroup);
        }
        if (_filterState != null) query = query.where('state', isEqualTo: _filterState);
        if (_filterDistrict != null) query = query.where('district', isEqualTo: _filterDistrict);

        final snap = await query.limit(50).get();
        var results = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

        // City filter — case insensitive client side
        if (_cityCtrl.text.trim().isNotEmpty) {
          final cityQuery = _cityCtrl.text.trim().toLowerCase();
          results = results.where((d) =>
              (d['city'] as String? ?? '').toLowerCase().contains(cityQuery)
          ).toList();
        }

        setState(() => _results = results);

      } else {
        // Search blood banks or hospitals
        final collection = _searchMode == 1 ? 'blood_banks' : 'hospitals';
        Query query = FirebaseFirestore.instance.collection(collection);

        if (_filterState != null) query = query.where('state', isEqualTo: _filterState);
        if (_filterDistrict != null) query = query.where('district', isEqualTo: _filterDistrict);

        final snap = await query.limit(50).get();
        var results = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

        // City filter — case insensitive
        if (_cityCtrl.text.trim().isNotEmpty) {
          final cityQuery = _cityCtrl.text.trim().toLowerCase();
          results = results.where((d) =>
              (d['city'] as String? ?? '').toLowerCase().contains(cityQuery)
          ).toList();
        }

        setState(() => _results = results);
      }
    } catch (_) {} finally {
      setState(() => _isSearching = false);
    }
  }

  void _clearFilters() => setState(() {
    _filterState = null;
    _filterDistrict = null;
    _districts = [];
    _cityCtrl.clear();
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

            const Text('Search & Request',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text('Find donors, blood banks or send SOS',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            // SOS Button
            GestureDetector(
              onTap: _sosActive ? null : () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => DraggableScrollableSheet(
                    initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
                    builder: (_, __) => SOSBottomSheet(
                      userData: widget.donorData,
                      primaryColor: widget.primaryColor,
                      onSOSSent: () => setState(() => _sosActive = true),
                    ),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _sosActive
                        ? [Colors.grey.shade400, Colors.grey.shade300]
                        : [color, color.withValues(alpha: 0.8)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _sosActive ? [] : [
                      BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 6))]),
                child: Column(children: [
                  Icon(Icons.sos_rounded, color: Colors.white, size: 36),
                  const SizedBox(height: 6),
                  Text(_sosActive ? 'SOS Sent! Help is on the way 🙏' : 'SOS — Emergency Blood Needed',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(_sosActive ? 'Nearby donors notified' : 'Tap to fill details & alert nearby donors',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                ]),
              ),
            ),

            const SizedBox(height: 24),

            // Search Mode Toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                _buildModeToggle('Donors', 0, Icons.favorite_rounded, color),
                _buildModeToggle('Blood Banks', 1, Icons.local_hospital_rounded, color),
                _buildModeToggle('Hospitals', 2, Icons.business_rounded, color),
              ]),
            ),

            const SizedBox(height: 20),

            // Blood group (donors only)
            if (_searchMode == 0) ...[
              const Text('Blood Group *',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: _bloodGroups.map((g) {
                final sel = _selectedBloodGroup == g;
                return GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); setState(() => _selectedBloodGroup = g); },
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 58, height: 42,
                      decoration: BoxDecoration(
                          color: sel ? color : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1),
                          boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)] : []),
                      child: Center(child: Text(g,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700)))),
                );
              }).toList()),
              const SizedBox(height: 16),
            ],

            // Location filter section header
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Location Filter',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              Row(children: [
                if (_hasActiveFilters)
                  GestureDetector(
                      onTap: _clearFilters,
                      child: Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red.shade400, fontWeight: FontWeight.w500))),
                if (_hasActiveFilters) const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _showFilters = !_showFilters),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _hasActiveFilters ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _hasActiveFilters ? color.withValues(alpha: 0.3) : Colors.grey.shade200)),
                    child: Row(children: [
                      Icon(_showFilters ? Icons.expand_less : Icons.tune_rounded,
                          size: 14, color: _hasActiveFilters ? color : Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_showFilters ? 'Hide' : 'Show${_hasActiveFilters ? ' ●' : ''}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                              color: _hasActiveFilters ? color : Colors.grey.shade600)),
                    ]),
                  ),
                ),
              ]),
            ]),

            const SizedBox(height: 10),

            // Location filter panel
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.15))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // State dropdown from JSON
                  const Text('State', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 6),
                  _loadingLocation
                      ? Center(child: CircularProgressIndicator(color: color, strokeWidth: 2))
                      : DropdownButtonFormField<String>(
                    value: _filterState,
                    isExpanded: true,
                    hint: Text('Select State', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    decoration: _filterInputDecoration(color),
                    items: _states.map((s) => DropdownMenuItem(
                        value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: _onStateChanged,
                    dropdownColor: Colors.white,
                    menuMaxHeight: 250,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
                  ),

                  const SizedBox(height: 10),

                  // District dropdown from JSON
                  const Text('District', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 6),
                  IgnorePointer(
                    ignoring: _filterState == null,
                    child: Opacity(
                      opacity: _filterState == null ? 0.5 : 1.0,
                      child: DropdownButtonFormField<String>(
                        value: _filterDistrict,
                        isExpanded: true,
                        hint: Text(_filterState == null ? 'Select State first' : 'Select District',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                        decoration: _filterInputDecoration(color),
                        items: _districts.map((d) => DropdownMenuItem(
                            value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: _filterState == null ? null : (val) => setState(() => _filterDistrict = val),
                        dropdownColor: Colors.white,
                        menuMaxHeight: 250,
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // City — type manually
                  const Text('City (type manually)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _cityCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                        hintText: 'Type city name',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: Icon(Icons.location_city_outlined, color: Colors.grey.shade400, size: 18),
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ]),
              ),
              secondChild: const SizedBox.shrink(),
            ),

            // Active filter chips
            if (_hasActiveFilters) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (_filterState != null) _buildChip(_filterState!, color, () => _onStateChanged(null)),
                if (_filterDistrict != null) _buildChip(_filterDistrict!, color, () => setState(() => _filterDistrict = null)),
                if (_cityCtrl.text.isNotEmpty) _buildChip(_cityCtrl.text, color, () { _cityCtrl.clear(); setState(() {}); }),
              ]),
            ],

            const SizedBox(height: 16),

            // Search button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _searchDonors,
                icon: _isSearching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search_rounded),
                label: Text(_isSearching ? 'Searching...' : _searchMode == 0 ? 'Search Donors' : _searchMode == 1 ? 'Search Blood Banks' : 'Search Hospitals'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
              ),
            ),

            const SizedBox(height: 20),

            // Results
            if (_results.isNotEmpty) ...[
              Text('${_results.length} result${_results.length > 1 ? 's' : ''} found',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              ..._results.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + i * 60),
                  builder: (context, val, child) => Opacity(
                      opacity: val, child: Transform.translate(offset: Offset(0, 20*(1-val)), child: child)),
                  child: _searchMode == 0 ? _buildDonorCard(d, color) : _buildOrgCard(d, color),
                );
              }),
            ] else if (!_isSearching) ...[
              Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Icon(Icons.search_rounded, size: 50, color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Text('Search to find results', style: TextStyle(color: Colors.grey.shade400, fontSize: 15)),
                ]),
              )),
            ],

          ]),
        ),
      ),
    );
  }

  Widget _buildModeToggle(String label, int index, IconData icon, Color color) {
    final active = _searchMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); setState(() { _searchMode = index; _results = []; _selectedBloodGroup = null; }); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              color: active ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.grey.shade500),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: active ? Colors.white : Colors.grey.shade500)),
          ]),
        ),
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

  Widget _buildChip(String label, Color color, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_on_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        GestureDetector(onTap: onRemove, child: Icon(Icons.close_rounded, size: 14, color: color)),
      ]),
    );
  }

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

  Widget _buildOrgCard(Map<String, dynamic> d, Color color) {
    final isBank = _searchMode == 1;
    final name = isBank ? (d['bank_name'] ?? 'Blood Bank') : (d['hospital_name'] ?? 'Hospital');
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(width: 46, height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
            child: Icon(isBank ? Icons.local_hospital_rounded : Icons.business_rounded, color: color, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 2),
          Text([d['city'], d['district'], d['state']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          if (d['phone'] != null && d['phone'].toString().isNotEmpty)
            Text(d['phone'], style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 16),
      ]),
    );
  }
}

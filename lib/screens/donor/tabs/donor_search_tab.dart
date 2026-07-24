import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String? _selectedBloodGroup;
  bool _isSearching = false;
  bool _sosActive = false;
  List<Map<String, dynamic>> _results = [];

  // Location filters
  String? _filterState;
  String? _filterDistrict;
  String? _filterCity;
  bool _showFilters = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  final TextEditingController _cityCtrl = TextEditingController();
  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  // India states for filter dropdown
  final List<String> _states = [
    'Andhra Pradesh','Arunachal Pradesh','Assam','Bihar','Chhattisgarh',
    'Goa','Gujarat','Haryana','Himachal Pradesh','Jharkhand','Karnataka',
    'Kerala','Madhya Pradesh','Maharashtra','Manipur','Meghalaya','Mizoram',
    'Nagaland','Odisha','Punjab','Rajasthan','Sikkim','Tamil Nadu','Telangana',
    'Tripura','Uttar Pradesh','Uttarakhand','West Bengal','Delhi','Chandigarh',
    'Puducherry','Jammu and Kashmir','Ladakh',
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchDonors() async {
    if (_selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please select a blood group'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    setState(() { _isSearching = true; _results = []; });

    try {
      Query query = FirebaseFirestore.instance
          .collection('donors')
          .where('blood_group', isEqualTo: _selectedBloodGroup)
          .where('is_available', isEqualTo: true);

      // Location filters
      if (_filterState != null && _filterState!.isNotEmpty) {
        query = query.where('state', isEqualTo: _filterState);
      }
      if (_filterDistrict != null && _filterDistrict!.isNotEmpty) {
        query = query.where('district', isEqualTo: _filterDistrict);
      }
      if (_cityCtrl.text.trim().isNotEmpty) {
        query = query.where('city', isEqualTo: _cityCtrl.text.trim());
      }

      final snap = await query.limit(20).get();
      setState(() {
        _results = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      });
    } catch (_) {} finally {
      setState(() => _isSearching = false);
    }
  }

  void _clearFilters() {
    setState(() {
      _filterState = null;
      _filterDistrict = null;
      _filterCity = null;
      _cityCtrl.clear();
    });
  }

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
            Text('Find donors or send emergency SOS',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 24),

            // SOS Button
            GestureDetector(
              onTap: _sosActive ? null : () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => DraggableScrollableSheet(
                    initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
                    builder: (_, controller) => SOSBottomSheet(
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
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _sosActive
                        ? [Colors.grey.shade400, Colors.grey.shade300]
                        : [color, color.withValues(alpha: 0.8)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _sosActive ? [] : [
                      BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 6))]),
                child: Column(children: [
                  Icon(Icons.sos_rounded, color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  Text(_sosActive ? 'SOS Sent! Help is on the way 🙏' : 'SOS — Emergency Blood Needed',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(_sosActive ? 'Nearby donors have been notified' : 'Tap to fill details & alert nearby donors',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                ]),
              ),
            ),

            const SizedBox(height: 28),

            // Search section header
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Find a Donor',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: _hasActiveFilters ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _hasActiveFilters ? color.withValues(alpha: 0.3) : Colors.grey.shade200)),
                  child: Row(children: [
                    Icon(Icons.tune_rounded, size: 14,
                        color: _hasActiveFilters ? color : Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('Filters${_hasActiveFilters ? ' ●' : ''}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                            color: _hasActiveFilters ? color : Colors.grey.shade600)),
                  ]),
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // Blood group selector
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

            // Location filters — expandable
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.15))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Location Filter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                      if (_hasActiveFilters)
                        GestureDetector(
                            onTap: _clearFilters,
                            child: Text('Clear all', style: TextStyle(fontSize: 12, color: Colors.red.shade400))),
                    ]),
                    const SizedBox(height: 12),

                    // State dropdown
                    const Text('State', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _filterState,
                      isExpanded: true,
                      hint: Text('Select State', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      decoration: InputDecoration(
                          filled: true, fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true),
                      items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (val) => setState(() { _filterState = val; _filterDistrict = null; }),
                      dropdownColor: Colors.white,
                      menuMaxHeight: 250,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
                    ),

                    const SizedBox(height: 10),

                    // District — manual type
                    const Text('District', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: _filterDistrict,
                      enabled: _filterState != null,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                          hintText: _filterState == null ? 'Select State first' : 'Type district name',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          filled: true, fillColor: _filterState != null ? Colors.white : Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true),
                      onChanged: (val) => setState(() => _filterDistrict = val.isEmpty ? null : val),
                    ),

                    const SizedBox(height: 10),

                    // City
                    const Text('City', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _cityCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                          hintText: 'Type city name',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
              ]),
              secondChild: const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),

            // Search button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSearching ? null : _searchDonors,
                icon: _isSearching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.search_rounded),
                label: Text(_isSearching ? 'Searching...' : 'Search Donors'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
              ),
            ),

            const SizedBox(height: 20),

            // Active filters display
            if (_hasActiveFilters) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_filterState != null) _buildFilterChip(_filterState!, color, () => setState(() => _filterState = null)),
                if (_filterDistrict != null) _buildFilterChip(_filterDistrict!, color, () => setState(() => _filterDistrict = null)),
                if (_cityCtrl.text.isNotEmpty) _buildFilterChip(_cityCtrl.text, color, () { _cityCtrl.clear(); setState(() {}); }),
              ]),
              const SizedBox(height: 16),
            ],

            // Results
            if (_results.isNotEmpty) ...[
              Text('${_results.length} donor${_results.length > 1 ? 's' : ''} found',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              ..._results.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 300 + i * 80),
                  builder: (context, val, child) => Opacity(
                      opacity: val, child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child)),
                  child: _buildDonorCard(d, color),
                );
              }),
            ] else if (!_isSearching && _selectedBloodGroup != null) ...[
              Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Icon(Icons.search_off_rounded, size: 50, color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Text('No donors found', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                  Text('Try different filters', style: TextStyle(color: Colors.grey.shade300, fontSize: 13)),
                ]),
              )),
            ],

          ]),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, Color color, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_on_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: color)),
      ]),
    );
  }

  Widget _buildDonorCard(Map<String, dynamic> d, Color color) {
    final isMe = d['uid'] == FirebaseAuth.instance.currentUser?.uid;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
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
          Text('${d['city'] ?? ''}${d['district'] != null ? ', ${d['district']}' : ''}${d['state'] != null ? ', ${d['state']}' : ''}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          if (d['age'] != null)
            Text('Age ${d['age']}', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        ])),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('Available', style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HospitalEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? hospitalData;
  final Color primaryColor;
  const HospitalEditProfileScreen({super.key, required this.hospitalData, required this.primaryColor});

  @override
  State<HospitalEditProfileScreen> createState() => _HospitalEditProfileScreenState();
}

class _HospitalEditProfileScreenState extends State<HospitalEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _licenseCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cityCtrl;

  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  String? _selectedState;
  String? _selectedDistrict;
  bool _loadingLocation = true;
  bool _saving = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final data = widget.hospitalData;
    _nameCtrl = TextEditingController(text: data?['hospital_name'] ?? '');
    _licenseCtrl = TextEditingController(text: data?['license_no'] ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone'] ?? '');
    _cityCtrl = TextEditingController(text: data?['city'] ?? '');
    _selectedState = (data?['state'] as String?)?.isNotEmpty == true ? data!['state'] : null;
    _selectedDistrict = (data?['district'] as String?)?.isNotEmpty == true ? data!['district'] : null;
    _loadLocationData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _licenseCtrl.dispose();
    _phoneCtrl.dispose();
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
        // Pre-fill district list if a state was already saved on the hospital doc.
        if (_selectedState != null && json[_selectedState] is Map) {
          _districts = (json[_selectedState] as Map<String, dynamic>).keys.toList()..sort();
          if (!_districts.contains(_selectedDistrict)) _selectedDistrict = null;
        }
        _loadingLocation = false;
      });
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  void _onStateChanged(String? state) {
    setState(() {
      _selectedState = state;
      _selectedDistrict = null;
      if (state != null) {
        final stateData = _locationData[state] as Map<String, dynamic>? ?? {};
        _districts = stateData.keys.toList()..sort();
      } else {
        _districts = [];
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_uid.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('hospitals').doc(_uid).update({
        'hospital_name': _nameCtrl.text.trim(),
        'license_no': _licenseCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'district': _selectedDistrict ?? '',
        'state': _selectedState ?? '',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save changes: $e'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _sectionLabel('Hospital Info', color),
              const SizedBox(height: 12),
              _field(
                controller: _nameCtrl,
                label: 'Hospital Name',
                icon: Icons.local_hospital_outlined,
                color: color,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter hospital name' : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _licenseCtrl,
                label: 'License No',
                icon: Icons.badge_outlined,
                color: color,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter license number' : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _phoneCtrl,
                label: 'Phone',
                icon: Icons.phone_outlined,
                color: color,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Enter phone number';
                  if (val.length < 10) return 'Enter a valid phone number';
                  return null;
                },
              ),

              const SizedBox(height: 24),
              _sectionLabel('Location', color),
              const SizedBox(height: 12),

              if (_loadingLocation)
                Center(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: color),
                ))
              else ...[
                _dropdownCard(
                  label: 'State',
                  icon: Icons.flag_outlined,
                  color: color,
                  value: _selectedState,
                  items: _states,
                  onChanged: _onStateChanged,
                ),
                const SizedBox(height: 14),
                _dropdownCard(
                  label: 'District',
                  icon: Icons.map_outlined,
                  color: color,
                  value: _selectedDistrict,
                  items: _districts,
                  onChanged: (v) => setState(() => _selectedDistrict = v),
                  enabled: _selectedState != null,
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _cityCtrl,
                  label: 'City',
                  icon: Icons.location_city_outlined,
                  color: color,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter city' : null,
                ),
              ],

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)));

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: color, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        ),
      ),
    );
  }

  Widget _dropdownCard({
    required String label,
    required IconData icon,
    required Color color,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : null,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: enabled ? onChanged : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: color, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        ),
      ),
    );
  }
}
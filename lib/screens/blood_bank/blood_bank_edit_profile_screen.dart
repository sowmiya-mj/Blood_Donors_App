import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BloodBankEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? bankData;
  final Color primaryColor;
  const BloodBankEditProfileScreen({super.key, required this.bankData, required this.primaryColor});

  @override
  State<BloodBankEditProfileScreen> createState() => _BloodBankEditProfileScreenState();
}

class _BloodBankEditProfileScreenState extends State<BloodBankEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _licenseCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _cityCtrl;

  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  String? _selectedState;
  String? _selectedDistrict;
  bool _loadingLocation = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.bankData;
    _nameCtrl = TextEditingController(text: data?['bank_name'] ?? '');
    _licenseCtrl = TextEditingController(text: data?['license_no'] ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone'] ?? '');
    _websiteCtrl = TextEditingController(text: data?['website'] ?? '');
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
    _websiteCtrl.dispose();
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
        if (_selectedState != null && json.containsKey(_selectedState)) {
          final stateData = json[_selectedState] as Map<String, dynamic>? ?? {};
          _districts = stateData.keys.toList()..sort();
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('blood_banks').doc(uid).update({
        'bank_name': _nameCtrl.text.trim(),
        'license_no': _licenseCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'state': _selectedState ?? '',
        'district': _selectedDistrict ?? '',
        'city': _cityCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully'), duration: Duration(seconds: 2)),
        );
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildLabel('Blood Bank Name'),
            _buildTextField(_nameCtrl, Icons.business_outlined, color,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),

            _buildLabel('License No'),
            _buildTextField(_licenseCtrl, Icons.badge_outlined, color,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),

            _buildLabel('Phone'),
            _buildTextField(_phoneCtrl, Icons.phone_outlined, color,
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 16),

            _buildLabel('Website'),
            _buildTextField(_websiteCtrl, Icons.language_outlined, color, keyboardType: TextInputType.url),
            const SizedBox(height: 20),

            _buildLabel('State'),
            const SizedBox(height: 6),
            _loadingLocation
                ? Center(child: CircularProgressIndicator(color: color, strokeWidth: 2))
                : DropdownButtonFormField<String>(
              value: _states.contains(_selectedState) ? _selectedState : null,
              isExpanded: true,
              hint: Text('Select State', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              decoration: _fieldDecoration(color),
              items: _states.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: _onStateChanged,
              dropdownColor: Colors.white,
              menuMaxHeight: 250,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),

            _buildLabel('District'),
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: _selectedState == null,
              child: Opacity(
                opacity: _selectedState == null ? 0.5 : 1.0,
                child: DropdownButtonFormField<String>(
                  value: _districts.contains(_selectedDistrict) ? _selectedDistrict : null,
                  isExpanded: true,
                  hint: Text(_selectedState == null ? 'Select State first' : 'Select District',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  decoration: _fieldDecoration(color),
                  items: _districts.map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: _selectedState == null ? null : (val) => setState(() => _selectedDistrict = val),
                  dropdownColor: Colors.white,
                  menuMaxHeight: 250,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey.shade400),
                ),
              ),
            ),
            const SizedBox(height: 16),

            _buildLabel('City'),
            _buildTextField(_cityCtrl, Icons.location_city_outlined, color,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.white,
                  disabledBackgroundColor: color.withValues(alpha: 0.6), elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
  );

  InputDecoration _fieldDecoration(Color color) => InputDecoration(
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _buildTextField(TextEditingController ctrl, IconData icon, Color color,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: _fieldDecoration(color).copyWith(prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20)),
      validator: validator,
    );
  }
}
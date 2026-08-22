import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecipientEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? recipientData;
  final Color primaryColor;

  const RecipientEditProfileScreen({
    super.key,
    required this.recipientData,
    required this.primaryColor,
  });

  @override
  State<RecipientEditProfileScreen> createState() => _RecipientEditProfileScreenState();
}

class _RecipientEditProfileScreenState extends State<RecipientEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _cityCtrl;

  String? _bloodGroup;
  String? _state;
  String? _district;

  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];
  bool _loadingLocation = true;
  bool _isSaving = false;

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    final data = widget.recipientData;
    _nameCtrl = TextEditingController(text: data?['name'] ?? '');
    _phoneCtrl = TextEditingController(text: data?['phone'] ?? '');
    _cityCtrl = TextEditingController(text: data?['city'] ?? '');
    _bloodGroup = data?['blood_group'];
    _state = data?['state'];
    _district = data?['district'];
    _loadLocationData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
        if (_state != null && _locationData[_state] != null) {
          final stateData = _locationData[_state] as Map<String, dynamic>;
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
      _state = state;
      _district = null;
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
    if (_bloodGroup == null) {
      _showSnack('Please select a blood group', isError: true);
      return;
    }
    if (_uid.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('recipients').doc(_uid).update({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'blood_group': _bloodGroup,
        'city': _cityCtrl.text.trim(),
        'district': _district,
        'state': _state,
      });
      if (!mounted) return;
      _showSnack('Profile updated');
      Navigator.pop(context, true);
    } catch (_) {
      _showSnack('Could not save changes. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  InputDecoration _fieldDecoration(String label, IconData icon, Color color) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade300)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              const Text('Personal Info',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameCtrl,
                decoration: _fieldDecoration('Full Name', Icons.person_outline, color),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: _fieldDecoration('Phone', Icons.phone_outlined, color),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Phone is required';
                  if (v.trim().length < 10) return 'Enter a valid phone number';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              const Text('Blood Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: _bloodGroups.map((g) {
                final sel = _bloodGroup == g;
                return GestureDetector(
                  onTap: () { HapticFeedback.lightImpact(); setState(() => _bloodGroup = g); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58, height: 42,
                    decoration: BoxDecoration(
                      color: sel ? color : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1),
                      boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)] : [],
                    ),
                    child: Center(child: Text(g,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : Colors.grey.shade700))),
                  ),
                );
              }).toList()),

              const SizedBox(height: 24),

              const Text('Location',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 12),

              const Text('State', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 6),
              _loadingLocation
                  ? Center(child: CircularProgressIndicator(color: color, strokeWidth: 2))
                  : DropdownButtonFormField<String>(
                value: _state,
                isExpanded: true,
                hint: Text('Select State', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                decoration: _fieldDecoration('', Icons.flag_outlined, color).copyWith(labelText: null),
                items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: _onStateChanged,
                dropdownColor: Colors.white,
                menuMaxHeight: 250,
              ),
              const SizedBox(height: 14),

              const Text('District', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 6),
              IgnorePointer(
                ignoring: _state == null,
                child: Opacity(
                  opacity: _state == null ? 0.5 : 1.0,
                  child: DropdownButtonFormField<String>(
                    value: _district,
                    isExpanded: true,
                    hint: Text(_state == null ? 'Select State first' : 'Select District',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    decoration: _fieldDecoration('', Icons.map_outlined, color).copyWith(labelText: null),
                    items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: _state == null ? null : (val) => setState(() => _district = val),
                    dropdownColor: Colors.white,
                    menuMaxHeight: 250,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _cityCtrl,
                decoration: _fieldDecoration('City', Icons.location_city_outlined, color),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'City is required' : null,
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }
}
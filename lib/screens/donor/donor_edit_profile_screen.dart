import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Pushed via Navigator.push, not a tab. Returns `true` via Navigator.pop
// when a save succeeds so the caller (DonorProfileTab) knows to refresh.
class DonorEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? donorData;
  final Color primaryColor;
  const DonorEditProfileScreen({super.key, required this.donorData, required this.primaryColor});
  @override
  State<DonorEditProfileScreen> createState() => _DonorEditProfileScreenState();
}

class _DonorEditProfileScreenState extends State<DonorEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _cityCtrl;
  String? _bloodGroup;
  String? _state;
  String? _district;
  bool _isSaving = false;
  bool _loadingLocation = true;
  Map<String, dynamic> _locationData = {};
  List<String> _states = [];
  List<String> _districts = [];

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    final d = widget.donorData;
    _nameCtrl = TextEditingController(text: d?['name'] ?? '');
    _phoneCtrl = TextEditingController(text: d?['phone'] ?? '');
    _ageCtrl = TextEditingController(text: d?['age']?.toString() ?? '');
    _cityCtrl = TextEditingController(text: d?['city'] ?? '');
    _bloodGroup = d?['blood_group'];
    _state = d?['state'];
    _district = d?['district'];
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocationData());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationData() async {
    try {
      final String data = await DefaultAssetBundle.of(context).loadString('assets/data/india_locations.json');
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
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('donors').doc(uid).update({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()),
        'city': _cityCtrl.text.trim(),
        'district': _district,
        'state': _state,
        if (_bloodGroup != null) 'blood_group': _bloodGroup,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Could not save changes. Try again.'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label('Full Name'),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration(color, hint: 'Your name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              _label('Phone'),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(color, hint: 'Phone number'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
              ),
              const SizedBox(height: 16),

              _label('Age'),
              TextFormField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(color, hint: 'Age'),
              ),
              const SizedBox(height: 16),

              _label('Blood Group'),
              const SizedBox(height: 8),
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
                          border: Border.all(color: sel ? color : Colors.grey.shade200, width: sel ? 2 : 1)),
                      child: Center(child: Text(g, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.grey.shade700)))),
                );
              }).toList()),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Only change this if your registered blood group was entered incorrectly.',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
              ),
              const SizedBox(height: 20),

              _label('Location'),
              const SizedBox(height: 8),
              _loadingLocation
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(children: [
                DropdownButtonFormField<String>(
                  value: _states.contains(_state) ? _state : null,
                  isExpanded: true,
                  decoration: _inputDecoration(color, hint: 'State'),
                  items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: _onStateChanged,
                  menuMaxHeight: 250,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _districts.contains(_district) ? _district : null,
                  isExpanded: true,
                  decoration: _inputDecoration(color, hint: _state == null ? 'Select state first' : 'District'),
                  items: _districts.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: _state == null ? null : (v) => setState(() => _district = v),
                  menuMaxHeight: 250,
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _cityCtrl,
                decoration: _inputDecoration(color, hint: 'City'),
              ),

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
  );

  InputDecoration _inputDecoration(Color color, {required String hint}) => InputDecoration(
    hintText: hint,
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
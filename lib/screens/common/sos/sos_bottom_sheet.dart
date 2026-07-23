import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../widgets/location_picker.dart';

class SOSBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final Color primaryColor;
  final VoidCallback onSOSSent;

  const SOSBottomSheet({
    super.key,
    required this.userData,
    required this.primaryColor,
    required this.onSOSSent,
  });

  @override
  State<SOSBottomSheet> createState() => _SOSBottomSheetState();
}

class _SOSBottomSheetState extends State<SOSBottomSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isSending = false;
  bool _changeLocation = false;
  bool _editingCity = false;

  String? _selectedBloodGroup;
  final _patientNameCtrl = TextEditingController();
  final _hospitalCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Location — pre-filled, changeable
  String _city = '';
  String _district = '';
  String _state = '';

  int _units = 1;

  late AnimationController _slideController;
  late Animation<double> _slideAnim;

  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  @override
  void initState() {
    super.initState();
    // Pre-fill from user data
    _patientNameCtrl.text = widget.userData?['name'] ?? '';
    _phoneCtrl.text = widget.userData?['phone'] ?? '';
    _city = widget.userData?['city'] ?? '';
    _district = widget.userData?['district'] ?? '';
    _state = widget.userData?['state'] ?? '';
    _selectedBloodGroup = widget.userData?['blood_group'];

    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = CurvedAnimation(parent: _slideController, curve: Curves.easeOut);
    _slideController.forward();
  }

  @override
  void dispose() {
    _patientNameCtrl.dispose(); _hospitalCtrl.dispose();
    _addressCtrl.dispose(); _phoneCtrl.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _sendSOS() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please select blood group'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    if (_city.isEmpty || _district.isEmpty || _state.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please complete location details'),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('sos_requests').add({
        'blood_group': _selectedBloodGroup,
        'patient_name': _patientNameCtrl.text.trim(),
        'hospital': _hospitalCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'city': _city,
        'district': _district,
        'state': _state,
        'units': _units,
        'status': 'active',
        'requester_uid': FirebaseAuth.instance.currentUser?.uid,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        widget.onSOSSent();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(_slideAnim),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.sos_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SOS Emergency Request',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                Text('Details pre-filled — edit if needed',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: Colors.grey.shade400),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Blood Group
                  const Text('Blood Group Required *',
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
                            color: sel ? Colors.red : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sel ? Colors.red : Colors.grey.shade200, width: sel ? 2 : 1),
                            boxShadow: sel ? [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 8)] : []),
                        child: Center(child: Text(g,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : Colors.grey.shade700))),
                      ),
                    );
                  }).toList()),

                  const SizedBox(height: 20),

                  // Units
                  const Text('Units Needed *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Row(children: [
                    _buildUnitBtn(Icons.remove, () { if (_units > 1) setState(() => _units--); }, Colors.grey.shade100, Colors.grey.shade700),
                    const SizedBox(width: 16),
                    Text('$_units unit${_units > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    const SizedBox(width: 16),
                    _buildUnitBtn(Icons.add, () { if (_units < 10) setState(() => _units++); }, Colors.red.shade50, Colors.red.shade600),
                  ]),

                  const SizedBox(height: 20),

                  // Patient name
                  _buildField(controller: _patientNameCtrl, label: 'Patient Name *',
                      hint: 'Full name of patient', icon: Icons.person_outline,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),

                  // Phone — pre-filled + editable
                  _buildField(controller: _phoneCtrl, label: 'Contact Number *',
                      hint: '+91 98765 43210', icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        final number = digits.startsWith('91') && digits.length == 12
                            ? digits.substring(2) : digits;
                        if (number.length != 10) return 'Enter valid 10-digit number';
                        return null;
                      }),
                  const SizedBox(height: 16),

                  // Hospital
                  _buildField(controller: _hospitalCtrl, label: 'Hospital / Location *',
                      hint: 'Apollo Hospital, Chennai', icon: Icons.local_hospital_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),

                  // Address
                  _buildField(controller: _addressCtrl, label: 'Address (optional)',
                      hint: 'Ward no, Floor, Room no', icon: Icons.location_on_outlined,
                      validator: null, maxLines: 2),
                  const SizedBox(height: 20),

                  // Location section
                  const Text('Location *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // State — display only (from location picker below)
                      _buildLocationRow(Icons.flag_outlined, 'State', _state),
                      const SizedBox(height: 8),
                      _buildLocationRow(Icons.map_outlined, 'District', _district),
                      const SizedBox(height: 10),

                      // City — with edit icon
                      Row(children: [
                        Icon(Icons.location_city_outlined, size: 16, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text('City: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        _editingCity
                            ? Expanded(child: TextField(
                          autofocus: true,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
                          decoration: InputDecoration(
                            hintText: 'Type city name',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
                          ),
                          onChanged: (v) => setState(() => _city = v),
                          onSubmitted: (_) => setState(() => _editingCity = false),
                        ))
                            : Expanded(child: Text(_city.isEmpty ? 'Not set' : _city,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)))),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _editingCity = !_editingCity),
                          child: Icon(_editingCity ? Icons.check_rounded : Icons.edit_rounded,
                              size: 16, color: _editingCity ? Colors.green : Colors.red.shade400),
                        ),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // Change State/District via picker
                  GestureDetector(
                    onTap: () => setState(() => _changeLocation = !_changeLocation),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _changeLocation ? Colors.red.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _changeLocation ? Colors.red.shade200 : Colors.grey.shade200),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_changeLocation ? Icons.close_rounded : Icons.swap_horiz_rounded,
                            size: 14, color: _changeLocation ? Colors.red : Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(_changeLocation ? 'Cancel' : 'Change State / District',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                                color: _changeLocation ? Colors.red : Colors.grey.shade600)),
                      ]),
                    ),
                  ),

                  if (_changeLocation) ...[
                    const SizedBox(height: 12),
                    LocationPicker(
                      color: Colors.red,
                      onLocationChanged: (state, district, city) {
                        setState(() {
                          if (state.isNotEmpty) _state = state;
                          if (district.isNotEmpty) _district = district;
                          // City from picker auto-fills too
                          if (city.isNotEmpty) {
                            _city = city;
                            _changeLocation = false;
                          }
                        });
                      },
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Send SOS button
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendSOS,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.red.shade300,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSending
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                        SizedBox(width: 10),
                        Text('Sending SOS...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ])
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.sos_rounded, size: 22),
                        SizedBox(width: 8),
                        Text('Send SOS Alert', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Center(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  )),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildUnitBtn(IconData icon, VoidCallback onTap, Color bg, Color iconColor) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey.shade400),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      Text(value.isEmpty ? 'Not set' : value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
    ]);
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: maxLines == 1 ? Icon(icon, color: Colors.grey.shade400, size: 20) : null,
          filled: true, fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade300)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // Fields
  String? _selectedBloodGroup;
  final _patientNameCtrl = TextEditingController();
  final _hospitalCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  int _units = 1;

  late AnimationController _slideController;
  late Animation<double> _slideAnim;

  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  @override
  void initState() {
    super.initState();
    // Pre-fill from user data
    _patientNameCtrl.text = widget.userData?['name'] ?? '';
    _cityCtrl.text = widget.userData?['city'] ?? '';
    _districtCtrl.text = widget.userData?['district'] ?? '';
    _stateCtrl.text = widget.userData?['state'] ?? '';
    _selectedBloodGroup = widget.userData?['blood_group'];

    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _slideAnim = CurvedAnimation(parent: _slideController, curve: Curves.easeOut);
    _slideController.forward();
  }

  @override
  void dispose() {
    _patientNameCtrl.dispose(); _hospitalCtrl.dispose();
    _addressCtrl.dispose(); _cityCtrl.dispose();
    _districtCtrl.dispose(); _stateCtrl.dispose();
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

    HapticFeedback.heavyImpact();
    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('sos_requests').add({
        'blood_group': _selectedBloodGroup,
        'patient_name': _patientNameCtrl.text.trim(),
        'hospital': _hospitalCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'district': _districtCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
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
    final color = widget.primaryColor;

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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.sos_rounded, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SOS Emergency Request',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                Text('Fill details to alert nearby donors',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]),
            ]),
          ),

          const SizedBox(height: 16),
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

                  // Units needed
                  const Text('Units Needed *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  Row(children: [
                    GestureDetector(
                      onTap: () { if (_units > 1) setState(() => _units--); HapticFeedback.lightImpact(); },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.remove, size: 20),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('$_units unit${_units > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () { if (_units < 10) setState(() => _units++); HapticFeedback.lightImpact(); },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.add, size: 20, color: Colors.red.shade600),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // Patient name
                  _buildField(controller: _patientNameCtrl, label: 'Patient Name *',
                      hint: 'Full name of patient', icon: Icons.person_outline,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),

                  // Hospital
                  _buildField(controller: _hospitalCtrl, label: 'Hospital / Location *',
                      hint: 'Apollo Hospital, Chennai', icon: Icons.local_hospital_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  const SizedBox(height: 16),

                  // Address
                  _buildField(controller: _addressCtrl, label: 'Address',
                      hint: 'Ward no, Floor, Room no (optional)', icon: Icons.location_on_outlined,
                      validator: null, maxLines: 2),
                  const SizedBox(height: 16),

                  // City + District row
                  Row(children: [
                    Expanded(child: _buildField(
                        controller: _cityCtrl, label: 'City *',
                        hint: 'Chennai', icon: Icons.location_city_outlined,
                        validator: (v) => v!.isEmpty ? 'Required' : null)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildField(
                        controller: _districtCtrl, label: 'District *',
                        hint: 'Chennai', icon: Icons.map_outlined,
                        validator: (v) => v!.isEmpty ? 'Required' : null)),
                  ]),
                  const SizedBox(height: 16),

                  // State
                  _buildField(controller: _stateCtrl, label: 'State *',
                      hint: 'Tamil Nadu', icon: Icons.flag_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null),

                  const SizedBox(height: 28),

                  // Send SOS button
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendSOS,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
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
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
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

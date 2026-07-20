import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../widgets/location_picker.dart'; // adjust path as needed

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with TickerProviderStateMixin {

  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  String? errorMessage;
  String? successMessage;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  bool alsoRecipient = false; // multi-role checkbox

  // Common controllers
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Donor / Recipient
  final _nameCtrl = TextEditingController();
  DateTime? _selectedDOB;
  String? _selectedBloodGroup;

  // Hospital / Blood Bank
  final _orgNameCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  // Location
  String _selectedState = '';
  String _selectedDistrict = '';
  String _selectedCity = '';

  final List<String> _bloodGroups = ['A+','A-','B+','B-','AB+','AB-','O+','O-'];

  // Animations
  late AnimationController _fadeController;
  late AnimationController _heartController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;
  late Animation<double> _heartAnim;
  late Animation<double> _shakeAnim;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 40, end: 0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _heartController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _heartAnim = Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeInOut));
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose(); _passwordCtrl.dispose(); _confirmPasswordCtrl.dispose();
    _phoneCtrl.dispose(); _nameCtrl.dispose(); _orgNameCtrl.dispose(); _licenseCtrl.dispose();
    _fadeController.dispose(); _heartController.dispose(); _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() { _shakeController.reset(); _shakeController.forward(); }

  Color get _roleColor {
    switch (widget.role.toLowerCase()) {
      case 'donor': return const Color(0xFFE53935);
      case 'recipient': return const Color(0xFF7B1FA2);
      case 'hospital': return const Color(0xFF1565C0);
      case 'blood bank': return const Color(0xFF2E7D32);
      default: return const Color(0xFFE53935);
    }
  }

  IconData get _roleIcon {
    switch (widget.role.toLowerCase()) {
      case 'donor': return Icons.favorite;
      case 'recipient': return Icons.bloodtype;
      case 'hospital': return Icons.local_hospital;
      case 'blood bank': return Icons.water_drop;
      default: return Icons.favorite;
    }
  }

  String get _roleTagline {
    switch (widget.role.toLowerCase()) {
      case 'donor': return 'Join thousands of\nlife savers today';
      case 'recipient': return 'Find blood\nin minutes';
      case 'hospital': return 'Manage emergency\nrequests efficiently';
      case 'blood bank': return 'Connect donors\nwith recipients';
      default: return 'Every drop\ncounts';
    }
  }

  int _calculateAge(DateTime dob) {
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    return age;
  }

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: _roleColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDOB = picked);
  }

  // Strong password validator
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    if (value.length < 8) return 'Min 8 characters';
    if (!value.contains(RegExp(r'[A-Z]'))) return 'Add at least 1 uppercase letter';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Add at least 1 number';
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return 'Add at least 1 special character (!@#\$...)';
    return null;
  }

  // Password strength indicator
  double _passwordStrength(String password) {
    double strength = 0;
    if (password.length >= 8) strength += 0.25;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.25;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.25;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.25;
    return strength;
  }

  Color _strengthColor(double strength) {
    if (strength <= 0.25) return Colors.red;
    if (strength <= 0.5) return Colors.orange;
    if (strength <= 0.75) return Colors.yellow.shade700;
    return Colors.green;
  }

  String _strengthLabel(double strength) {
    if (strength <= 0.25) return 'Weak';
    if (strength <= 0.5) return 'Fair';
    if (strength <= 0.75) return 'Good';
    return 'Strong';
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) { _triggerShake(); return; }
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => errorMessage = 'Passwords do not match');
      _triggerShake(); return;
    }
    final role = widget.role.toLowerCase();
    if ((role == 'donor' || role == 'recipient') && _selectedBloodGroup == null) {
      setState(() => errorMessage = 'Please select your blood group');
      _triggerShake(); return;
    }
    if (role == 'donor' && _selectedDOB == null) {
      setState(() => errorMessage = 'Please select your date of birth');
      _triggerShake(); return;
    }
    if (_selectedState.isEmpty || _selectedDistrict.isEmpty || _selectedCity.isEmpty) {
      setState(() => errorMessage = 'Please complete location selection');
      _triggerShake(); return;
    }

    setState(() { isLoading = true; errorMessage = null; });

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final uid = cred.user!.uid;

      // Base user data
      final baseData = {
        'uid': uid,
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'state': _selectedState,
        'district': _selectedDistrict,
        'city': _selectedCity,
        'createdAt': FieldValue.serverTimestamp(),
      };

      switch (role) {
        case 'donor':
          await _db.collection('donors').doc(uid).set({
            ...baseData,
            'name': _nameCtrl.text.trim(),
            'dob': DateFormat('yyyy-MM-dd').format(_selectedDOB!),
            'age': _calculateAge(_selectedDOB!),
            'blood_group': _selectedBloodGroup,
            'role': 'donor',
            'is_available': true,
          });
          // Multi-role: also register as recipient if checked
          if (alsoRecipient) {
            await _db.collection('recipients').doc(uid).set({
              ...baseData,
              'name': _nameCtrl.text.trim(),
              'blood_group': _selectedBloodGroup,
              'role': 'recipient',
            });
          }
          break;

        case 'recipient':
          await _db.collection('recipients').doc(uid).set({
            ...baseData,
            'name': _nameCtrl.text.trim(),
            'blood_group': _selectedBloodGroup,
            'role': 'recipient',
          });
          break;

        case 'hospital':
          await _db.collection('hospitals').doc(uid).set({
            ...baseData,
            'hospital_name': _orgNameCtrl.text.trim(),
            'license_no': _licenseCtrl.text.trim(),
            'role': 'hospital',
            'verified': false,
          });
          break;

        case 'blood bank':
          await _db.collection('blood_banks').doc(uid).set({
            ...baseData,
            'bank_name': _orgNameCtrl.text.trim(),
            'license_no': _licenseCtrl.text.trim(),
            'role': 'blood_bank',
            'verified': false,
          });
          break;
      }

      setState(() => successMessage = 'Account created successfully! 🎉');
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context); // TODO: → Dashboard

    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'email-already-in-use': errorMessage = 'Email already registered. Try logging in'; break;
          case 'weak-password': errorMessage = 'Password is too weak'; break;
          case 'invalid-email': errorMessage = 'Invalid email address'; break;
          default: errorMessage = 'Registration failed. Please try again';
        }
      });
      _triggerShake();
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 700;
    final color = _roleColor;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: isDesktop ? _buildDesktopLayout(color) : _buildMobileLayout(color),
      ),
    );
  }

  Widget _buildDesktopLayout(Color color) {
    return Row(children: [
      Expanded(flex: 4, child: _buildIllustrationPanel(color)),
      Expanded(flex: 6, child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: _buildFormPanel(color)),
        ),
      )),
    ]);
  }

  Widget _buildMobileLayout(Color color) {
    return SingleChildScrollView(child: Column(children: [
      _buildIllustrationPanel(color, isMobile: true),
      Padding(padding: const EdgeInsets.all(24), child: _buildFormPanel(color)),
    ]));
  }

  Widget _buildIllustrationPanel(Color color, {bool isMobile = false}) {
    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) => Opacity(opacity: _fadeAnim.value, child: child),
      child: Container(
        height: isMobile ? 220 : double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04), Colors.white]),
        ),
        child: Stack(children: [
          Positioned(top: -40, left: -40, child: Container(width: 200, height: 200,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.08)))),
          Positioned(bottom: -30, right: -30, child: Container(width: 150, height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.06)))),
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ScaleTransition(scale: _heartAnim,
                child: Container(width: isMobile ? 80 : 110, height: isMobile ? 80 : 110,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12),
                        border: Border.all(color: color.withValues(alpha: 0.3), width: 2)),
                    child: Icon(_roleIcon, size: isMobile ? 38 : 55, color: color))),
            SizedBox(height: isMobile ? 12 : 24),
            Text('Blood Readiness', style: TextStyle(fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold, color: color)),
            Text('Network', style: TextStyle(fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold, color: color)),
            SizedBox(height: isMobile ? 6 : 10),
            Text(_roleTagline, textAlign: TextAlign.center,
                style: TextStyle(fontSize: isMobile ? 12 : 14, color: Colors.grey.shade600, height: 1.5)),
          ])),
        ]),
      ),
    );
  }

  Widget _buildFormPanel(Color color) {
    final passwordValue = _passwordCtrl.text;
    final strength = _passwordStrength(passwordValue);

    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) => Opacity(opacity: _fadeAnim.value,
          child: Transform.translate(offset: Offset(0, _slideAnim.value), child: child)),
      child: AnimatedBuilder(
        animation: _shakeAnim,
        builder: (context, child) {
          final shake = (_shakeAnim.value * 3).round().toDouble();
          final offset = shake % 2 == 0 ? shake * 3 : -shake * 3;
          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
        child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Create Account', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text('Register as ${widget.role}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 6),
          Row(children: [
            Text('Already have an account? ', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Text('Login here', style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: color)),
            ),
          ]),
          const SizedBox(height: 28),

          // Role-specific fields
          ..._buildRoleFields(color),
          const SizedBox(height: 16),

          // Common fields
          _buildField(controller: _emailCtrl, label: 'Email address', hint: 'you@example.com', icon: Icons.email_outlined, color: color, keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'Required' : !v.contains('@') || !v.contains('.') ? 'Enter a valid email' : null),
          const SizedBox(height: 16),
          _buildField(controller: _phoneCtrl, label: 'Phone number', hint: '+91 98765 43210', icon: Icons.phone_outlined, color: color, keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 16),

          // Location picker
          LocationPicker(
            color: color,
            onLocationChanged: (state, district, city) {
              setState(() { _selectedState = state; _selectedDistrict = district; _selectedCity = city; });
            },
          ),
          const SizedBox(height: 16),

          // Password with strength indicator
          _buildField(controller: _passwordCtrl, label: 'Password', hint: 'Min 8 chars, uppercase, number, symbol', icon: Icons.lock_outline, color: color,
              isPassword: true, isObscure: obscurePassword, onToggle: () => setState(() => obscurePassword = !obscurePassword),
              validator: _validatePassword,
              onChanged: (_) => setState(() {})),

          // Password strength bar
          if (_passwordCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: strength, backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(_strengthColor(strength)), minHeight: 5))),
              const SizedBox(width: 10),
              Text(_strengthLabel(strength), style: TextStyle(fontSize: 12, color: _strengthColor(strength), fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 16),

          _buildField(controller: _confirmPasswordCtrl, label: 'Confirm Password', hint: '••••••••', icon: Icons.lock_outline, color: color,
              isPassword: true, isObscure: obscureConfirm, onToggle: () => setState(() => obscureConfirm = !obscureConfirm),
              validator: (v) => v!.isEmpty ? 'Required' : v != _passwordCtrl.text ? 'Passwords do not match' : null),

          // Multi-role checkbox (Donor only)
          if (widget.role.toLowerCase() == 'donor') ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: CheckboxListTile(
                value: alsoRecipient,
                onChanged: (val) => setState(() => alsoRecipient = val ?? false),
                activeColor: color,
                title: Text('I also want to register as Recipient', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1A1A2E))),
                subtitle: Text('You can both donate and request blood', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],

          // Error / Success
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            _buildMessageBox(errorMessage!, isError: true),
          ],
          if (successMessage != null) ...[
            const SizedBox(height: 12),
            _buildMessageBox(successMessage!, isError: false),
          ],

          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : _handleRegister,
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
                  disabledBackgroundColor: color.withValues(alpha: 0.6), elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey.shade500),
            label: Text('Back to Login', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          )),
        ])),
      ),
    );
  }

  List<Widget> _buildRoleFields(Color color) {
    final role = widget.role.toLowerCase();
    switch (role) {
      case 'donor':
      case 'recipient':
        return [
          _buildField(controller: _nameCtrl, label: 'Full Name', hint: 'Your full name', icon: Icons.person_outline, color: color,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 16),
          if (role == 'donor') ...[
            // DOB Picker
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Date of Birth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDOB,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _selectedDOB != null ? color : Colors.grey.shade200)),
                  child: Row(children: [
                    Icon(Icons.cake_outlined, color: Colors.grey.shade400, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      _selectedDOB != null
                          ? '${DateFormat('dd MMM yyyy').format(_selectedDOB!)}  •  Age: ${_calculateAge(_selectedDOB!)} yrs'
                          : 'Select date of birth (must be 18+)',
                      style: TextStyle(fontSize: 14, color: _selectedDOB != null ? const Color(0xFF1A1A2E) : Colors.grey.shade400),
                    )),
                    Icon(Icons.calendar_today_outlined, color: color, size: 18),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          _buildBloodGroupPicker(color),
        ];

      case 'hospital':
      case 'blood bank':
        return [
          _buildField(
              controller: _orgNameCtrl,
              label: role == 'hospital' ? 'Hospital Name' : 'Blood Bank Name',
              hint: role == 'hospital' ? 'Apollo Hospital' : 'City Blood Bank',
              icon: Icons.business_outlined, color: color,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 16),
          _buildField(controller: _licenseCtrl, label: 'License Number', hint: 'LIC-2024-XXXXX', icon: Icons.badge_outlined, color: color,
              validator: (v) => v!.isEmpty ? 'Required' : null),
        ];

      default: return [];
    }
  }

  Widget _buildBloodGroupPicker(Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Blood Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: _bloodGroups.map((group) {
        final selected = _selectedBloodGroup == group;
        return GestureDetector(
          onTap: () => setState(() => _selectedBloodGroup = group),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58, height: 42,
            decoration: BoxDecoration(
              color: selected ? color : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? color : Colors.grey.shade200, width: selected ? 2 : 1),
            ),
            child: Center(child: Text(group, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700))),
          ),
        );
      }).toList()),
    ]);
  }

  Widget _buildMessageBox(String message, {required bool isError}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: isError ? Colors.red.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isError ? Colors.red.shade200 : Colors.green.shade200)),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade600 : Colors.green.shade600, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: isError ? Colors.red.shade700 : Colors.green.shade700, fontSize: 13))),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    bool isPassword = false,
    bool isObscure = false,
    VoidCallback? onToggle,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Function(String)? onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        obscureText: isPassword ? isObscure : false,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15),
        validator: validator,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
          suffixIcon: isPassword ? IconButton(
              icon: Icon(isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20),
              onPressed: onToggle) : null,
          filled: true, fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade300)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    ]);
  }
}

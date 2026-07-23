import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../screens/donor/donor_dashboard.dart';
import '../../screens/recipient/recipient_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isLoading = false;
  bool isGoogleLoading = false;
  String? errorMessage;

  late AnimationController _fadeController;
  late AnimationController _heartController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _heartAnimation;
  late Animation<double> _shakeAnimation;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnimation = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _heartController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _heartAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _fadeController.forward();

    // v7: initialize() must be called once before any other method
    GoogleSignIn.instance.initialize(
      clientId: '768808579408-7324ar7dec8ahhfe3c87t6g1te8k9vc2.apps.googleusercontent.com',
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _fadeController.dispose();
    _heartController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.reset();
    _shakeController.forward();
  }

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
      case 'donor': return 'Your blood can\nsave 3 lives';
      case 'recipient': return 'Find blood\nin minutes';
      case 'hospital': return 'Manage emergency\nrequests efficiently';
      case 'blood bank': return 'Connect donors\nwith recipients';
      default: return 'Every drop\ncounts';
    }
  }

  Future<void> _handleEmailLogin() async {
    if (emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
      setState(() => errorMessage = 'Please fill in all fields');
      _triggerShake();
      return;
    }
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      // Role validation — Firestore check
      final uid = cred.user!.uid;
      final role = widget.role.toLowerCase();
      final collection = role == 'donor' ? 'donors'
          : role == 'recipient' ? 'recipients'
          : role == 'hospital' ? 'hospitals'
          : 'blood_banks';

      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .get();

      if (!doc.exists) {
        // Wrong role — logout பண்ணிட்டு error காட்டு
        await FirebaseAuth.instance.signOut();
        setState(() => errorMessage =
        'No ${widget.role} account found for this email.\nPlease register as ${widget.role} first.');
        _triggerShake();
        return;
      }

      // Correct role — navigate
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => role == 'donor'
                ? const DonorDashboard()
                : const RecipientDashboard(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found': errorMessage = 'No account found with this email'; break;
          case 'wrong-password': errorMessage = 'Incorrect password'; break;
          case 'invalid-email': errorMessage = 'Invalid email address'; break;
          case 'user-disabled': errorMessage = 'This account has been disabled'; break;
          case 'too-many-requests': errorMessage = 'Too many attempts. Try again later'; break;
          default: errorMessage = 'Login failed. Please try again';
        }
      });
      _triggerShake();
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() { isGoogleLoading = true; errorMessage = null; });
    try {
      // v7: authenticate() replaces signIn()
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) { setState(() => isGoogleLoading = false); return; }

      // v7: authentication is now SYNCHRONOUS - no await!
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      // TODO: Navigator.pushReplacement to dashboard
    } on GoogleSignInException catch (e) {
      setState(() => errorMessage = 'Google Sign In failed: ${e.code.name}');
      _triggerShake();
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = e.message ?? 'Authentication failed');
      _triggerShake();
    } catch (e) {
      setState(() => errorMessage = 'Google Sign In failed. Try again');
      _triggerShake();
    } finally {
      setState(() => isGoogleLoading = false);
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
      Expanded(flex: 5, child: _buildIllustrationPanel(color)),
      Expanded(flex: 5, child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _buildFormPanel(color),
          ),
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
      animation: _fadeAnimation,
      builder: (context, child) => Opacity(opacity: _fadeAnimation.value, child: child),
      child: Container(
        height: isMobile ? 260 : double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.12),
              color.withValues(alpha: 0.04),
              Colors.white,
            ],
          ),
        ),
        child: Stack(children: [
          Positioned(top: -40, left: -40, child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.08)),
          )),
          Positioned(bottom: -30, right: -30, child: Container(
            width: 150, height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.06)),
          )),
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ScaleTransition(
              scale: _heartAnimation,
              child: Container(
                width: isMobile ? 90 : 130,
                height: isMobile ? 90 : 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(_roleIcon, size: isMobile ? 44 : 65, color: color),
              ),
            ),
            SizedBox(height: isMobile ? 16 : 32),
            Text('Blood Readiness', style: TextStyle(fontSize: isMobile ? 20 : 28, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
            Text('Network', style: TextStyle(fontSize: isMobile ? 20 : 28, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
            SizedBox(height: isMobile ? 8 : 16),
            Text(_roleTagline, textAlign: TextAlign.center,
                style: TextStyle(fontSize: isMobile ? 13 : 16, color: Colors.grey.shade600, height: 1.5)),
            if (!isMobile) ...[
              const SizedBox(height: 48),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _buildStat('10K+', 'Donors', color),
                const SizedBox(width: 32),
                _buildStat('500+', 'Blood Banks', color),
                const SizedBox(width: 32),
                _buildStat('98%', 'Success Rate', color),
              ]),
            ],
          ])),
        ]),
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
    ]);
  }

  Widget _buildFormPanel(Color color) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) => Opacity(
        opacity: _fadeAnimation.value,
        child: Transform.translate(offset: Offset(0, _slideAnimation.value), child: child),
      ),
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          final shake = (_shakeAnimation.value * 3).round().toDouble();
          final offset = shake % 2 == 0 ? shake * 3 : -shake * 3;
          return Transform.translate(offset: Offset(offset, 0), child: child);
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Welcome back', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text('Login as ${widget.role}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 6),
          Row(children: [
            Text("Don't have an account? ", style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            GestureDetector(
              onTap: () { Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RegisterScreen(role: widget.role),
                ),
              ); },
              child: Text('Register here', style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: color)),
            ),
          ]),
          const SizedBox(height: 36),
          _buildTextField(controller: emailController, label: 'Email address', hint: 'you@example.com', icon: Icons.email_outlined, color: color, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          _buildTextField(controller: passwordController, label: 'Password', hint: '••••••••', icon: Icons.lock_outline, color: color, isPassword: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () { Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(roleColor: _roleColor)));},
              style: TextButton.styleFrom(foregroundColor: color, padding: EdgeInsets.zero),
              child: const Text('Forgot password?', style: TextStyle(fontSize: 13)),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : _handleEmailLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                disabledBackgroundColor: color.withValues(alpha: 0.6),
                elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or continue with', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton(
              onPressed: isGoogleLoading ? null : _handleGoogleSignIn,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: Colors.white,
              ),
              child: isGoogleLoading
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: color, strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
                const SizedBox(width: 10),
                Text('Sign in with Google', style: TextStyle(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey.shade500),
              label: Text('Change role', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color color,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        obscureText: isPassword ? obscurePassword : false,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
          suffixIcon: isPassword ? IconButton(
            icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20),
            onPressed: () => setState(() => obscurePassword = !obscurePassword),
          ) : null,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    ]);
  }
}

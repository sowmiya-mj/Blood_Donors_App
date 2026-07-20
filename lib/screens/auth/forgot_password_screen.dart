import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final Color roleColor;
  const ForgotPasswordScreen({super.key, required this.roleColor});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  bool isLoading = false;
  bool emailSent = false;
  String? errorMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 30, end: 0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => errorMessage = 'Please enter your email');
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => errorMessage = 'Invalid email address');
      return;
    }
    setState(() { isLoading = true; errorMessage = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      setState(() { emailSent = true; });
    } on FirebaseAuthException catch (e) {
      setState(() {
        switch (e.code) {
          case 'user-not-found': errorMessage = 'No account found with this email'; break;
          case 'invalid-email': errorMessage = 'Invalid email address'; break;
          default: errorMessage = 'Failed to send reset email. Try again';
        }
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.roleColor;
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: color, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 48 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedBuilder(
                animation: _fadeAnim,
                builder: (context, child) => Opacity(
                  opacity: _fadeAnim.value,
                  child: Transform.translate(offset: Offset(0, _slideAnim.value), child: child),
                ),
                child: emailSent ? _buildSuccessView(color) : _buildFormView(color),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 70, height: 70,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.1)),
        child: Icon(Icons.lock_reset_rounded, size: 36, color: color),
      ),
      const SizedBox(height: 24),
      const Text('Forgot Password?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      Text("No worries! Enter your email and we'll send a reset link.", style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
      const SizedBox(height: 32),
      const Text('Email address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 8),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'you@example.com',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.email_outlined, color: Colors.grey.shade400, size: 20),
          filled: true, fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      if (errorMessage != null) ...[
        const SizedBox(height: 12),
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
          onPressed: isLoading ? null : _sendResetEmail,
          style: ElevatedButton.styleFrom(
            backgroundColor: color, foregroundColor: Colors.white,
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Send Reset Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios, size: 14, color: Colors.grey.shade500),
          label: Text('Back to Login', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ),
      ),
    ]);
  }

  Widget _buildSuccessView(Color color) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
      const SizedBox(height: 40),
      Container(
        width: 100, height: 100,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.shade50),
        child: Icon(Icons.mark_email_read_outlined, size: 52, color: Colors.green.shade600),
      ),
      const SizedBox(height: 28),
      const Text('Check your email!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 12),
      Text(
        'We sent a password reset link to\n${_emailCtrl.text.trim()}',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.6),
      ),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: color, foregroundColor: Colors.white,
            elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Back to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: _sendResetEmail,
        child: Text("Didn't receive? Resend", style: TextStyle(color: color, fontSize: 13)),
      ),
    ]);
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth
import '../theme/theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  String? _focusedField;
  bool _isLoading = false; // Loading State
  late AnimationController _blobController;

  @override
  void initState() {
    super.initState();
    // Blob Animation
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

    // Focus Listener
    _emailFocus.addListener(() {
      setState(() => _focusedField = _emailFocus.hasFocus ? 'email' : null);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    _blobController.dispose();
    super.dispose();
  }

  // --- RESET PASSWORD LOGIC ---
  Future<void> _handleReset() async {
    String email = _emailController.text.trim();

    // 1. Validation
    if (email.isEmpty) {
      _showSnackBar("Please enter your email address", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Firebase Call
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      // 3. Success Dialog
      _showSuccessDialog(email);

    } on FirebaseAuthException catch (e) {
      String msg = "Error sending email";
      if (e.code == 'user-not-found') msg = "No user found with this email.";
      else if (e.code == 'invalid-email') msg = "Invalid email format.";
      _showSnackBar(msg, Colors.red);
    } catch (e) {
      _showSnackBar("Something went wrong. Try again.", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SUCCESS DIALOG ---
  void _showSuccessDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.mark_email_read, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            const Text("Check Inbox"),
          ],
        ),
        content: Text(
          "We have sent a password reset link to:\n$email\n\nPlease check your email (and spam folder) to reset your password.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close Dialog
              Navigator.pop(context); // Go back to Login
            },
            child: Text("Back to Login", style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: theme.primaryColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppTheme.getGradient(theme.brightness),
              ),
            ),
          ),

          // 2. Animated Blobs
          _buildAnimatedBlob(
              top: size.height * 0.1, right: -60,
              color: theme.primaryColor.withOpacity(0.15),
              size: 250, scaleOffset: 0.2
          ),
          _buildAnimatedBlob(
              bottom: size.height * 0.1, left: -60,
              color: AppTheme.uolSecondary.withOpacity(0.15),
              size: 250, scaleOffset: 0.7
          ),

          // 3. Main Content
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.15),

                // Icon / Logo Area
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.lock_reset_outlined, color: Colors.white, size: 40),
                ),

                const SizedBox(height: 24),

                // Headlines
                Text(
                  "Forgot Password?",
                  style: theme.textTheme.headlineLarge?.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "Enter your registered email address to receive a password reset link.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7)),
                  ),
                ),

                const SizedBox(height: 40),

                // Glass Card
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Email Address", style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),

                      // Input Field
                      _buildThemeInputField(
                          controller: _emailController,
                          focusNode: _emailFocus,
                          icon: Icons.email_outlined,
                          hint: "student@student.uol.edu.pk",
                          isFocused: _focusedField == 'email',
                          theme: theme
                      ),

                      const SizedBox(height: 30),

                      // Submit Button
                      Container(
                        width: double.infinity, height: 55,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoading ? null : _handleReset, // Logic Linked
                            borderRadius: BorderRadius.circular(12),
                            child: Center(
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                  : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text("Send Reset Link", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8),
                                  Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget for Input Field
  Widget _buildThemeInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required String hint,
    required bool isFocused,
    required ThemeData theme
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(12),
        border: isFocused
            ? Border.all(color: theme.inputDecorationTheme.focusedBorder!.borderSide.color, width: 2)
            : Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
        boxShadow: isFocused ? [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 10)] : [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: isFocused ? theme.iconTheme.color : theme.iconTheme.color?.withOpacity(0.5), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller, focusNode: focusNode,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                hintText: hint, hintStyle: theme.inputDecorationTheme.hintStyle, isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Blob Animation Helper
  Widget _buildAnimatedBlob({double? top, double? left, double? bottom, double? right, required Color color, required double size, required double scaleOffset}) {
    return Positioned(
      top: top, left: left, bottom: bottom, right: right,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (context, child) {
          double scale = 1.0 + (sin(_blobController.value * 2 * pi + scaleOffset) * 0.2);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: size, height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)]),
            ),
          );
        },
      ),
    );
  }
}
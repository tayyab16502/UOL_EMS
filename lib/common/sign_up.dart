import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore

// --- IMPORT GOOGLE SIGN IN & NAVIGATION ---
import 'package:google_sign_in/google_sign_in.dart' as google_lib;
import '../student/student_dashboard.dart'; // Navigation
import '../admin/admin_dashboard.dart';   // Navigation

import '../theme/theme.dart';
import 'info.dart'; // Navigation to Profile Completion
import 'login.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // --- DEPARTMENTS LIST ---
  final List<String> _departments = [
    'Computer Science',
    'Pharmacy',
    'Urdu',
    'Physics',
    'Mathematics & Statistics',
    'Chemistry',
    'Zoology',
    'Psychology',
    'English Language & Literature',
    'Education',
    'Islamic Studies',
    'Accounting & Finance'
  ];
  String? _selectedDepartment; // Stores User Selection

  // State Variables
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _agreedToTerms = false;
  bool _isLoading = false;
  bool _verificationEmailSent = false;

  // Focus & Animation
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();
  String? _focusedField;
  late AnimationController _blobController;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

    _emailFocus.addListener(() { setState(() => _focusedField = _emailFocus.hasFocus ? 'email' : null); });
    _passwordFocus.addListener(() { setState(() => _focusedField = _passwordFocus.hasFocus ? 'password' : null); });
    _confirmPasswordFocus.addListener(() { setState(() => _focusedField = _confirmPasswordFocus.hasFocus ? 'confirmPassword' : null); });
  }

  @override
  void dispose() {
    _emailController.dispose(); _passwordController.dispose(); _confirmPasswordController.dispose();
    _emailFocus.dispose(); _passwordFocus.dispose(); _confirmPasswordFocus.dispose();
    _blobController.dispose(); super.dispose();
  }

  // --- 1. AUTO DEPARTMENT CREATION LOGIC ---
  Future<void> _ensureDepartmentExists(String deptName) async {
    final deptRef = FirebaseFirestore.instance.collection('departments').doc(deptName);
    final doc = await deptRef.get();

    if (!doc.exists) {
      await deptRef.set({
        'name': deptName,
        'isLocked': false, // Default unlocked
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // --- 2. EMAIL SIGN UP LOGIC ---
  Future<void> _handleSignUp() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    String confirm = _confirmPasswordController.text.trim();

    // Validation
    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showSnackBar("Please fill all fields", Colors.red);
      return;
    }
    if (_selectedDepartment == null) {
      _showSnackBar("Please select your Department", Colors.red);
      return;
    }
    if (password != confirm) {
      _showSnackBar("Passwords do not match", Colors.red);
      return;
    }
    if (!email.endsWith('@student.uol.edu.pk') && !email.endsWith('@uol.edu.pk')) {
      _showSnackBar("Please use UOL official email (@student.uol.edu.pk)", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create User in Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Send Verification Email
      if (userCredential.user != null && !userCredential.user!.emailVerified) {
        await userCredential.user!.sendEmailVerification();
      }

      setState(() {
        _verificationEmailSent = true;
        _isLoading = false;
      });

      _showSnackBar("Account created! Verification email sent.", Colors.green);

    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String msg = "Signup failed";
      if (e.code == 'weak-password') msg = "Password is too weak.";
      else if (e.code == 'email-already-in-use') msg = "Email already registered.";
      _showSnackBar(msg, Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  // --- 3. CHECK VERIFICATION LOGIC (UPDATED STATUS) ---
  Future<void> _checkEmailVerified() async {
    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {

        // --- STEP: CREATE INITIAL DATA ---
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (!doc.exists) {
          // 1. Save User directly to 'users' collection with 'pending' status
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'email': user.email,
            'role': 'student', // Default Role
            'department': _selectedDepartment, // Save Selected Dept
            'createdAt': FieldValue.serverTimestamp(),
            'uid': user.uid,
            // --- UPDATED LOGIC HERE ---
            'status': 'pending', // User is pending admin approval
            'isApproved': false, // Explicitly false
          });

          // 2. Ensure Department Exists
          if (_selectedDepartment != null) {
            await _ensureDepartmentExists(_selectedDepartment!);
          }
        }

        if (!mounted) return;

        _showSnackBar("Verification Successful! Complete your profile.", Colors.green);

        // --- NAVIGATION ---
        // We still send them to InfoScreen to fill details,
        // but Login will block them until 'status' becomes 'approved'.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => InfoScreen(email: user!.email!)),
        );

      } else {
        _showSnackBar("Email not verified yet. Please check your inbox.", Colors.orange);
      }
    } catch (e) {
      _showSnackBar("Verification check failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 4. RESEND EMAIL ---
  Future<void> _resendEmail() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _showSnackBar("Verification email sent again!", Colors.blue);
    } catch (e) {
      _showSnackBar("Failed to resend: $e", Colors.red);
    }
  }

  // --- 5. GOOGLE SIGN UP LOGIC (UPDATED STATUS) ---
  Future<void> _handleGoogleSignUp() async {
    setState(() => _isLoading = true);
    try {
      final google_lib.GoogleSignIn googleSignIn = google_lib.GoogleSignIn();
      await googleSignIn.signOut();

      final google_lib.GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (!googleUser.email.endsWith('@student.uol.edu.pk') && !googleUser.email.endsWith('@uol.edu.pk')) {
        await googleSignIn.signOut();
        setState(() => _isLoading = false);
        _showSnackBar("Only UOL official emails allowed.", Colors.red);
        return;
      }

      final google_lib.GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // Check Existing User
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          // --- EXISTING USER ---
          Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
          String role = data['role'] ?? 'student';

          if (!user.emailVerified) {
            _emailController.text = user.email!;
            setState(() { _verificationEmailSent = true; _isLoading = false; });
            try { await user.sendEmailVerification(); } catch (_) {}
            return;
          }

          if (!mounted) return;
          _navigateBasedOnRole(role, user.email!);

        } else {
          // --- NEW USER (UPDATED STATUS) ---
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'email': user.email,
            'fullName': user.displayName ?? 'Student',
            'role': 'student',
            'department': 'General', // Default, update in Info Screen
            'createdAt': FieldValue.serverTimestamp(),
            'uid': user.uid,
            // --- UPDATED LOGIC HERE ---
            'status': 'pending', // User is pending admin approval
            'isApproved': false, // Explicitly false
            'profileImage': user.photoURL ?? ''
          });

          if (user.emailVerified) {
            if (!mounted) return;
            // Proceed to Info Screen to complete profile (Admin will approve later)
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => InfoScreen(email: user.email!)));
          } else {
            _emailController.text = user.email!;
            setState(() { _verificationEmailSent = true; _isLoading = false; });
            try { await user.sendEmailVerification(); } catch (_) {}
          }
        }
      }

    } catch (e) {
      debugPrint("Google Sign Up Error: $e");
      _showSnackBar("Google Sign Up Failed. Error: $e", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- NAVIGATION HELPER ---
  void _navigateBasedOnRole(String role, String email) {
    Widget targetScreen;
    if (role == 'admin') {
      _showSnackBar("Welcome back Admin!", Colors.green);
      targetScreen = AdminDashboard(userEmail: email);
    } else {
      _showSnackBar("Welcome back!", Colors.green);
      targetScreen = StudentDashboard(userEmail: email);
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => targetScreen),
          (route) => false,
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppTheme.getGradient(brightness),
              ),
            ),
          ),
          _buildAnimatedBlob(top: size.height * 0.1, left: -50, color: theme.primaryColor.withOpacity(0.15), size: 250, scaleOffset: 0),
          _buildAnimatedBlob(bottom: size.height * 0.1, right: -50, color: AppTheme.uolSecondary.withOpacity(0.15), size: 250, scaleOffset: 0.5),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Icon(
                        _verificationEmailSent ? Icons.mark_email_unread : Icons.person_add,
                        color: Colors.white, size: 30
                    ),
                  ),
                  const SizedBox(height: 12),

                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]).createShader(bounds),
                    child: Text(
                        _verificationEmailSent ? "Verify Email" : "Join UOL EMS",
                        style: theme.textTheme.headlineLarge?.copyWith(fontSize: 28, letterSpacing: 0.5)
                    ),
                  ),

                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: _verificationEmailSent
                        ? _buildVerificationUI(theme)
                        : _buildSignupForm(theme),
                  ),

                  const SizedBox(height: 20),

                  if (!_verificationEmailSent)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Have an account? ", style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13)),
                        GestureDetector(
                            onTap: () { Navigator.pop(context); },
                            child: Text("Sign in", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13))
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI PART 1: SIGNUP FORM ---
  Widget _buildSignupForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThemeInputField(controller: _emailController, focusNode: _emailFocus, icon: Icons.mail_outline, hint: "Student Email", isFocused: _focusedField == 'email', theme: theme),
        const SizedBox(height: 16),
        _buildThemeInputField(controller: _passwordController, focusNode: _passwordFocus, icon: Icons.lock_outline, hint: "Password", isFocused: _focusedField == 'password', theme: theme, isPassword: true, isVisible: _isPasswordVisible, onVisibilityToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible)),
        const SizedBox(height: 16),
        _buildThemeInputField(controller: _confirmPasswordController, focusNode: _confirmPasswordFocus, icon: Icons.verified_user_outlined, hint: "Confirm Password", isFocused: _focusedField == 'confirmPassword', theme: theme, isPassword: true, isVisible: _isConfirmVisible, onVisibilityToggle: () => setState(() => _isConfirmVisible = !_isConfirmVisible)),

        const SizedBox(height: 16),

        // --- DEPARTMENT DROPDOWN ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          decoration: BoxDecoration(
            color: theme.inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedDepartment,
              hint: Row(children: [
                Icon(Icons.apartment, color: theme.iconTheme.color?.withOpacity(0.5), size: 18),
                const SizedBox(width: 10),
                Text("Select Department", style: theme.inputDecorationTheme.hintStyle?.copyWith(fontSize: 13))
              ]),
              icon: Icon(Icons.arrow_drop_down, color: theme.primaryColor),
              items: _departments.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: theme.textTheme.bodyMedium),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _selectedDepartment = newValue;
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // --- SIGN UP BUTTON ---
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_isLoading) ? null : _handleSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Container(
                alignment: Alignment.center,
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Create Account", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),
        Row(children: [Expanded(child: Divider(color: theme.dividerColor)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("OR", style: TextStyle(fontSize: 12, color: Colors.grey.shade500))), Expanded(child: Divider(color: theme.dividerColor))]),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _handleGoogleSignUp,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.g_mobiledata, size: 35, color: theme.primaryColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Sign up with Google",
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- UI PART 2: VERIFICATION UI ---
  Widget _buildVerificationUI(ThemeData theme) {
    return Column(
      children: [
        Text(
          "We sent a verification link to\n${_emailController.text}",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Note: If you don't see the email in your Inbox, please check your Spam/Junk folder.",
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        Container(
          width: double.infinity, height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading ? null : _checkEmailVerified,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("I HAVE VERIFIED", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),

        const SizedBox(height: 15),

        TextButton.icon(
          onPressed: _isLoading ? null : _resendEmail,
          icon: Icon(Icons.refresh, size: 16, color: theme.primaryColor),
          label: Text("Resend Email", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
        ),

        const SizedBox(height: 10),

        TextButton(
          onPressed: () => setState(() => _verificationEmailSent = false),
          child: Text("Change Email", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildThemeInputField({required TextEditingController controller, required FocusNode focusNode, required IconData icon, required String hint, required bool isFocused, required ThemeData theme, bool isPassword = false, bool isVisible = false, VoidCallback? onVisibilityToggle}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(10),
        border: isFocused ? Border.all(color: theme.inputDecorationTheme.focusedBorder!.borderSide.color, width: 2) : Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
        boxShadow: isFocused ? [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 8)] : [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: Row(
        children: [
          Icon(icon, color: isFocused ? theme.iconTheme.color : theme.iconTheme.color?.withOpacity(0.5), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller, focusNode: focusNode, obscureText: isPassword && !isVisible,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              decoration: InputDecoration(
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                hintText: hint, hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(fontSize: 13), isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (isPassword)
            GestureDetector(
              onTap: onVisibilityToggle,
              child: Icon(isVisible ? Icons.visibility_off : Icons.visibility, color: theme.iconTheme.color?.withOpacity(0.5), size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({double? top, double? left, double? bottom, double? right, required Color color, required double size, required double scaleOffset}) {
    return Positioned(
      top: top, left: left, bottom: bottom, right: right,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (context, child) {
          double scale = 1.0 + (sin(_blobController.value * 2 * pi + scaleOffset) * 0.2);
          return Transform.scale(
            scale: scale,
            child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])),
          );
        },
      ),
    );
  }
}
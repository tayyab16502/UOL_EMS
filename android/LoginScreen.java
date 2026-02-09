import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart'; // REQUIRED IMPORT
import '../theme/theme.dart';
import '../theme/theme_manager.dart';
import 'sign_up.dart';
import 'reset_password.dart';
import 'info.dart';
import '../student/student_dashboard.dart';
import '../admin/admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State Variables
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // Focus Nodes & Animation
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  String? _focusedField;
  late AnimationController _blobController;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

    _emailFocus.addListener(() { setState(() => _focusedField = _emailFocus.hasFocus ? 'email' : null); });
    _passwordFocus.addListener(() { setState(() => _focusedField = _passwordFocus.hasFocus ? 'password' : null); });
  }

  @override
  void dispose() {
    _emailController.dispose(); _passwordController.dispose();
    _emailFocus.dispose(); _passwordFocus.dispose();
    _blobController.dispose(); super.dispose();
  }

  // --- 1. EMAIL LOGIN LOGIC ---
  Future<void> _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Please enter email and password", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;
      if (user != null) {
        await _checkUserRoleAndNavigate(user);
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Login failed";
      if (e.code == 'user-not-found') msg = "No user found with this email.";
      else if (e.code == 'wrong-password') msg = "Incorrect password.";
      else if (e.code == 'invalid-credential') msg = "Invalid email or password.";
      _showSnackBar(msg, Colors.red);
      setState(() => _isLoading = false);
    } catch (e) {
      _showSnackBar("An error occurred: $e", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- 2. GOOGLE LOGIN LOGIC (FIXED) ---
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // 1. Create Instance (Fix for the getter error)
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // 2. Trigger Google Flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false); // User cancelled
        return;
      }

      // 3. Domain Check
      if (!googleUser.email.endsWith('@student.uol.edu.pk') && !googleUser.email.endsWith('@uol.edu.pk')) {
        await googleSignIn.signOut();
        setState(() => _isLoading = false);
        _showSnackBar("Only UOL emails allowed.", Colors.red);
        return;
      }

      // 4. Auth with Firebase
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        await _checkUserRoleAndNavigate(user, isGoogleLogin: true);
      }

    } catch (e) {
      debugPrint("Google Sign In Error: $e");
      // Agar error aye to ye check karein k SHA-1 key Firebase console ma add ha ya nahi
      _showSnackBar("Google Sign In Failed. Please try again.", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- 3. CENTRAL NAVIGATION LOGIC ---
  Future<void> _checkUserRoleAndNavigate(User user, {bool isGoogleLogin = false}) async {
    try {
      // A. Super Admin Check
      if (user.email == 'tayyabkhan190247@gmail.com') {
        if (!mounted) return;
        _navigateBasedOnRole('admin', user.email!);
        return;
      }

      // B. Check Admin Collection
      DocumentSnapshot adminDoc = await FirebaseFirestore.instance.collection('admin').doc(user.uid).get();
      if (adminDoc.exists) {
        Map<String, dynamic> data = adminDoc.data() as Map<String, dynamic>;
        if (data.containsKey('isDarkMode')) themeManager.toggleTheme(data['isDarkMode']);
        
        if (!mounted) return;
        _navigateBasedOnRole('admin', user.email!);
        return;
      }

      // C. Check Users Collection
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        // Existing User found
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('isDarkMode')) themeManager.toggleTheme(data['isDarkMode']);

        String role = data['role'] ?? 'student';
        
        // Email Verification Check (Skip for Google & Admin)
        if (!isGoogleLogin && !user.emailVerified && role != 'admin') {
          await FirebaseAuth.instance.signOut();
          _showSnackBar("Please verify your email address first.", Colors.orange);
          setState(() => _isLoading = false);
          return;
        }

        if (!mounted) return;
        _navigateBasedOnRole(role, user.email!); // Navigate to Student Dashboard

      } else {
        // D. NEW USER SCENARIO (Google Only)
        // Agar Google se login kia magar user database ma nahi ha to naya account banao
        if (isGoogleLogin) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'email': user.email,
            'fullName': user.displayName ?? 'Student',
            'role': 'student',
            'createdAt': FieldValue.serverTimestamp(),
            'uid': user.uid,
            'status': 'onboarding', // Send to Info Screen
            'profileImage': user.photoURL ?? ''
          });

          if (!mounted) return;
          // Navigate to Info Screen to fill missing details
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => InfoScreen(email: user.email!)));
        } else {
          // Zombie Account (Email login but no doc)
          await FirebaseAuth.instance.signOut();
          _showSnackBar("Account not found. Please Sign Up.", Colors.red);
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      _showSnackBar("Error checking role: $e", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- NAVIGATION HELPER ---
  void _navigateBasedOnRole(String role, String email) {
    Widget targetScreen;

    if (role == 'admin') {
      _showSnackBar("Welcome Admin!", Colors.green);
      targetScreen = AdminDashboard(userEmail: email);
    } else {
      // Default for Students & Guards
      _showSnackBar("Welcome!", Colors.green);
      targetScreen = StudentDashboard(userEmail: email);
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => targetScreen),
          (route) => false,
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppTheme.getGradient(brightness),
              ),
            ),
          ),

          // Blobs
          _buildAnimatedBlob(top: size.height * 0.2, left: -50, color: theme.primaryColor.withOpacity(0.15), size: 300, scaleOffset: 0),
          _buildAnimatedBlob(bottom: size.height * 0.2, right: -50, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, scaleOffset: 0.5),

          // Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]).createShader(bounds),
                    child: Text("UOL EMS", style: theme.textTheme.headlineLarge?.copyWith(fontSize: 40, letterSpacing: 1.0)),
                  ),
                  const SizedBox(height: 8),
                  Text("Sign in to your account", style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 40),

                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Email", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        _buildThemeInputField(controller: _emailController, focusNode: _emailFocus, icon: Icons.person_outline, hint: "Enter your email", isFocused: _focusedField == 'email', theme: theme),

                        const SizedBox(height: 24),

                        Text("Password", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        _buildThemeInputField(controller: _passwordController, focusNode: _passwordFocus, icon: Icons.lock_outline, hint: "Enter your password", isFocused: _focusedField == 'password', theme: theme, isPassword: true),

                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ResetPasswordScreen())),
                            child: Text("Forgot password?", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Login Button
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
                              onTap: _isLoading ? null : _handleLogin,
                              borderRadius: BorderRadius.circular(12),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Sign In", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.arrow_forward, color: Colors.white, size: 20)]),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // OR Divider
                        Row(children: [Expanded(child: Divider(color: theme.dividerColor)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("OR", style: TextStyle(fontSize: 12, color: Colors.grey.shade500))), Expanded(child: Divider(color: theme.dividerColor))]),
                        
                        const SizedBox(height: 20),

                        // Google Sign In Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                            // Ensure 'assets/google_logo.png' exists in pubspec.yaml
                            // Use Icon fallback if image fails
                            icon: Image.asset('assets/google_logo.png', height: 20), 
                            label: Text("Sign in with Google", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: theme.dividerColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account? ", style: theme.textTheme.bodyMedium),
                      GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpScreen())),
                          child: Text("Sign up", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold))
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

  Widget _buildThemeInputField({required TextEditingController controller, required FocusNode focusNode, required IconData icon, required String hint, required bool isFocused, required ThemeData theme, bool isPassword = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(12),
        border: isFocused ? Border.all(color: theme.inputDecorationTheme.focusedBorder!.borderSide.color, width: 2) : Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
        boxShadow: isFocused ? [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 10)] : [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: isFocused ? theme.iconTheme.color : theme.iconTheme.color?.withOpacity(0.5), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller, focusNode: focusNode, obscureText: isPassword && !_isPasswordVisible,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, hintText: hint, hintStyle: theme.inputDecorationTheme.hintStyle, isDense: true),
            ),
          ),
          if (isPassword)
            GestureDetector(
              onTap: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              child: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility, color: theme.iconTheme.color?.withOpacity(0.5), size: 20),
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
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Google Sign In Alias
import 'package:google_sign_in/google_sign_in.dart' as google_lib;

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

  // --- [NEW LOGIC START] AUTOMATED DEPARTMENT CREATOR ---
  // Ye check karega k Admin ka department folder DB ma ha ya nahi. Nahi ha to bana dega.
  Future<void> _ensureDepartmentExists(String deptName) async {
    try {
      String cleanName = deptName.trim();
      // 'General' ya empty name k liye folder nahi banana
      if (cleanName.isEmpty || cleanName == 'General') return;

      DocumentReference deptRef = FirebaseFirestore.instance.collection('departments').doc(cleanName);
      DocumentSnapshot doc = await deptRef.get();

      if (!doc.exists) {
        // Create Department Automatically (Unlocked by default)
        await deptRef.set({
          'name': cleanName,
          'isLocked': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint("Auto-created department folder: $cleanName");
      }
    } catch (e) {
      debugPrint("Error checking/creating department: $e");
    }
  }
  // --- [NEW LOGIC END] ---

  // --- DEPARTMENT LOCK CHECKER ---
  Future<bool> _isDepartmentLocked(String? deptName) async {
    if (deptName == null || deptName == 'Computer Science' || deptName == 'CS') {
      return false; // Boss/CS Always Open
    }
    try {
      DocumentSnapshot deptDoc = await FirebaseFirestore.instance.collection('departments').doc(deptName).get();
      if (deptDoc.exists) {
        return deptDoc.get('isLocked') == true;
      }
      return false;
    } catch (e) {
      return false;
    }
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
      // 1. Auth Check
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // 2. DB Check (Zombie Check)
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          // --- NORMAL USER FLOW ---
          Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

          // Case Insensitive Role Check ("Admin" -> "admin")
          String role = (data['role'] ?? 'student').toString().toLowerCase();
          String dept = (data['department'] ?? 'General').toString().trim();

          // --- [STUDENT APPROVAL CHECK] ---
          if (role == 'student') {
            bool isApproved = data['isApproved'] == true;
            if (!isApproved) {
              await FirebaseAuth.instance.signOut();
              _showSnackBar("Access Denied: Your account is pending Admin approval.", Colors.red);
              setState(() => _isLoading = false);
              return;
            }
          }

          // --- [ADMIN FOLDER CHECK] ---
          if (role == 'admin') {
            await _ensureDepartmentExists(dept);
          }

          // 3. Lock Check
          bool locked = await _isDepartmentLocked(dept);
          if (locked) {
            await FirebaseAuth.instance.signOut();
            _showSnackBar("Access Denied: The $dept Department is currently locked.", Colors.red);
            setState(() => _isLoading = false);
            return;
          }

          // 4. Sync Theme
          if (data.containsKey('isDarkMode')) themeManager.toggleTheme(data['isDarkMode']);

          // 5. Navigate
          if (!mounted) return;
          if (role == 'admin') {
            _navigateBasedOnRole('admin', user.email!);
          } else {
            _navigateBasedOnRole('student', user.email!);
          }

        } else {
          // --- [UPDATED ZOMBIE LOGIC] ---
          // Scenario: Auth main user ha, lekin DB main data nahi ha.
          // Action: User ko Auth se delete karo taakay wo dobara fresh Sign Up kar sakay.
          try {
            await user.delete();
            _showSnackBar("Corrupted Account Detected. Your ID has been reset. Please Sign Up again.", Colors.orange);
          } catch (deleteError) {
            // Agar delete fail ho (mostly requires-recent-login), to sirf sign out kar do.
            await FirebaseAuth.instance.signOut();
            _showSnackBar("Account Data Missing. Please contact support.", Colors.red);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Login failed";
      if (e.code == 'user-not-found') msg = "No user found with this email.";
      else if (e.code == 'wrong-password') msg = "Incorrect password.";
      _showSnackBar(msg, Colors.red);
    } catch (e) {
      _showSnackBar("An error occurred: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. GOOGLE SIGN IN LOGIC ---
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final google_lib.GoogleSignIn googleSignIn = google_lib.GoogleSignIn();
      await googleSignIn.signOut(); // Force Account Picker

      final google_lib.GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
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
        await _checkGoogleUserRole(user);
      }

    } catch (e) {
      debugPrint("Google Sign In Error: $e");
      _showSnackBar("Google Login Failed.", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- 3. GOOGLE USER ROLE CHECK (LOGIC CORE) ---
  Future<void> _checkGoogleUserRole(User user) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        // --- SCENARIO A: OLD USER (LOGIN) ---
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

        String role = (data['role'] ?? 'student').toString().toLowerCase();
        String dept = (data['department'] ?? 'General').toString().trim();

        // Check Approval
        if (role == 'student') {
          bool isApproved = data['isApproved'] == true;
          if (!isApproved) {
            await FirebaseAuth.instance.signOut();
            _showSnackBar("Access Denied: Your account is pending Admin approval.", Colors.red);
            setState(() => _isLoading = false);
            return;
          }
        }

        // Admin Folder Check
        if (role == 'admin') {
          await _ensureDepartmentExists(dept);
        }

        // Lock Check
        bool locked = await _isDepartmentLocked(dept);
        if (locked) {
          await FirebaseAuth.instance.signOut();
          _showSnackBar("Access Denied: The $dept Department is locked.", Colors.red);
          setState(() => _isLoading = false);
          return;
        }

        if (!mounted) return;
        _navigateBasedOnRole(role, user.email!);

      } else {
        // --- SCENARIO B: NEW USER (ACCOUNT CREATION) ---
        // Note: Google Sign In auto-fixes Zombies by creating the account here if missing.

        String email = user.email ?? "";
        if (!email.endsWith('@student.uol.edu.pk') && !email.endsWith('@uol.edu.pk')) {
          await FirebaseAuth.instance.signOut();
          _showSnackBar("Registration Restricted: Use UOL official email only.", Colors.red);
          setState(() => _isLoading = false);
          return;
        }

        // Create Account (isApproved defaults to false/null)
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'fullName': user.displayName ?? 'Student',
          'role': 'student',
          'department': 'General',
          'createdAt': FieldValue.serverTimestamp(),
          'uid': user.uid,
          'status': 'onboarding',
          'isApproved': false, // Explicitly false
          'profileImage': user.photoURL ?? ''
        });

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => InfoScreen(email: user.email!)));
      }
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // --- NAVIGATION ---
  void _navigateBasedOnRole(String role, String email) {
    Widget targetScreen;

    if (role == 'admin') {
      _showSnackBar("Welcome Admin!", Colors.green);
      targetScreen = AdminDashboard(userEmail: email);
    } else {
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
                        Row(children: [Expanded(child: Divider(color: theme.dividerColor)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("OR", style: TextStyle(fontSize: 12, color: Colors.grey.shade500))), Expanded(child: Divider(color: theme.dividerColor))]),
                        const SizedBox(height: 20),

                        // GOOGLE BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
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
                                    "Sign in with Google",
                                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
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
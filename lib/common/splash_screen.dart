import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore
import 'package:shared_preferences/shared_preferences.dart'; // LOCAL STORAGE
import '../theme/theme.dart';
import '../theme/theme_manager.dart'; // Theme Manager
import 'login.dart';
import 'info.dart';
import '../admin/admin_dashboard.dart';
import '../student/student_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _blobController;
  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;
  late Animation<double> _textSlide;

  @override
  void initState() {
    super.initState();

    // 1. Setup Animations
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = CurvedAnimation(parent: _logoController, curve: Curves.elasticOut);

    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    _textSlide = Tween<double>(begin: 20.0, end: 0.0).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));

    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);

    // 2. Add Listener to Theme Manager (For Real-time update on Splash)
    themeManager.addListener(_onThemeChanged);

    // 3. Load Theme from Memory Immediately
    _loadLocalTheme();

    // 4. Start Logic
    _startAnimationAndAuth();
  }

  // --- FORCE REBUILD WHEN THEME CHANGES ---
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  // --- LOAD THEME INSTANTLY ---
  Future<void> _loadLocalTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool? isDark = prefs.getBool('isDarkMode');

      if (isDark != null) {
        // Agar memory ma saved ha to foran apply karo
        themeManager.toggleTheme(isDark);
        // Force UI update immediately
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Error loading local theme: $e");
    }
  }

  // --- SAVE THEME LOCALLY (Helper) ---
  Future<void> _saveLocalTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }

  // --- MAIN LOGIC ---
  void _startAnimationAndAuth() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _textController.forward();

    // Branding Wait
    await Future.delayed(const Duration(seconds: 2));

    _checkUserSession();
  }

  Future<void> _checkUserSession() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;

        if (refreshedUser != null) {
          await _decideNavigation(refreshedUser.uid, refreshedUser.email!);
        } else {
          _navigateToLogin();
        }
      } on FirebaseAuthException {
        _navigateToLogin();
      } catch (e) {
        _navigateToLogin();
      }
    } else {
      _navigateToLogin();
    }
  }

  // --- NAVIGATION LOGIC ---
  Future<void> _decideNavigation(String uid, String email) async {
    if (!mounted) return;

    // Hardcoded Super Admin Check (Optional Safety)
    if (email == 'tayyabkhan190247@gmail.com') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AdminDashboard(userEmail: email)));
      return;
    }

    try {
      // --- 1. CHECK USERS COLLECTION (Flat Structure) ---
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;

        // Identify Role
        String role = (data['role'] ?? 'student').toString().toLowerCase();
        String status = data['status'] ?? 'pending';

        // Sync Theme (DB -> Local)
        if (data.containsKey('isDarkMode')) {
          bool dbTheme = data['isDarkMode'];
          themeManager.toggleTheme(dbTheme);
          _saveLocalTheme(dbTheme);
        }

        if (!mounted) return;

        // --- LOGIC UPDATE START ---
        if (role == 'admin') {
          // ADMIN: Bypass Status Check. Always go to Admin Dashboard.
          // Because admins are manually created and trusted.
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => AdminDashboard(userEmail: email)));
        }
        else {
          // STUDENT: Must be Approved or Active
          if (status == 'active' || status == 'approved') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => StudentDashboard(userEmail: email)));
          } else {
            // If Student is Pending -> Send to Waiting Screen
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const VerificationPendingScreen()));
          }
        }
        // --- LOGIC UPDATE END ---
      }
      else {
        // User authenticated but no record in DB -> Go to Login/Signup
        _navigateToLogin();
      }
    } catch (e) {
      _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    // Remove listener to prevent memory leaks
    themeManager.removeListener(_onThemeChanged);
    _logoController.dispose();
    _textController.dispose();
    _blobController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- DIRECT CHECK FROM MANAGER FOR INSTANT UPDATE ---
    final isDark = themeManager.isDarkMode;
    // Get colors based on ThemeManager state directly (faster than context propagation)
    final List<Color> bgColors = AppTheme.getGradient(isDark ? Brightness.dark : Brightness.light);
    final Color textColor = isDark ? Colors.white : AppTheme.uolPrimary;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bgColors,
          ),
        ),
        child: Stack(
          children: [
            _buildAnimatedBlob(
                top: 40, left: 40,
                color: AppTheme.uolPrimary.withOpacity(0.2),
                size: 150, scaleOffset: 0
            ),
            _buildAnimatedBlob(
                bottom: 80, right: 80,
                color: AppTheme.uolSecondary.withOpacity(0.2),
                size: 200, scaleOffset: 0.5
            ),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Welcome Text
                  FadeTransition(
                    opacity: _textOpacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Welcome UOL Students",
                          style: TextStyle( // Using manual style to avoid context lag
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Poppins'
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.auto_awesome, color: Colors.green, size: 20),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Logo
                  ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.uolPrimary, AppTheme.uolSecondary],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.uolPrimary.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.school_outlined, size: 80, color: Colors.white),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Title Animation
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: Opacity(
                          opacity: _textOpacity.value,
                          child: Column(
                            children: [
                              ShaderMask(
                                shaderCallback: (bounds) => const LinearGradient(
                                  colors: [AppTheme.uolPrimary, AppTheme.uolSecondary],
                                ).createShader(bounds),
                                child: Text(
                                  "UOL EMS",
                                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                    fontSize: 40,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 100, height: 4,
                                decoration: BoxDecoration(
                                    color: AppTheme.uolSecondary,
                                    borderRadius: BorderRadius.circular(20)
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                  "Event Management System",
                                  style: TextStyle(
                                      color: textColor.withOpacity(0.8),
                                      fontSize: 14,
                                      fontFamily: 'Poppins'
                                  )
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 50),

                  // Loading Dots
                  FadeTransition(
                    opacity: _textOpacity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) => _buildLoadingDot(index)),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 30, left: 0, right: 0,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Center(
                  child: Text(
                    "Your event. Your control.",
                    style: TextStyle(fontSize: 10, letterSpacing: 2, color: AppTheme.uolPrimary.withOpacity(0.5), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBlob({double? top, double? left, double? bottom, double? right, required Color color, required double size, required double scaleOffset}) {
    return Positioned(
      top: top, left: left, bottom: bottom, right: right,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (context, child) {
          double scale = 1.0 + (sin(_blobController.value * 2 * pi + scaleOffset) * 0.1);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: size, height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 40)]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingDot(int index) {
    return AnimatedBuilder(
      animation: _blobController,
      builder: (context, child) {
        double value = sin((_blobController.value * 2 * pi) + (index * 0.5));
        double opacity = 0.4 + (value.abs() * 0.6);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 10, height: 10,
          decoration: BoxDecoration(color: AppTheme.uolPrimary.withOpacity(opacity), shape: BoxShape.circle),
        );
      },
    );
  }
}
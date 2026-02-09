import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/theme.dart';
import '../common/profile.dart'; // For profile editing if needed

class RegisterEventScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;

  const RegisterEventScreen({super.key, required this.eventData});

  @override
  State<RegisterEventScreen> createState() => _RegisterEventScreenState();
}

class _RegisterEventScreenState extends State<RegisterEventScreen> {
  int _currentStep = 1;
  String _qrData = "";
  bool _isLoading = false;
  bool _isFetchingProfile = true;

  // Real Profile Data
  String _name = "Loading...";
  String _regId = "...";
  String _dept = "...";
  String _program = "...";
  String _userId = "";

  @override
  void initState() {
    super.initState();
    _secureScreen(); // Block Screenshots
    _fetchUserDataAndCheckRegistration();
  }

  // --- 1. FETCH DATA & CHECK DUPLICATE ---
  Future<void> _fetchUserDataAndCheckRegistration() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userId = user.uid;

    try {
      // A. Check if already registered
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']).get();
      if (eventDoc.exists) {
        List registered = eventDoc.get('registeredStudents') ?? [];
        if (registered.contains(_userId)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are already registered for this event!"), backgroundColor: Colors.orange));
          Navigator.pop(context); // Go back immediately
          return;
        }
      }

      // B. Fetch Profile Data
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _name = data['fullName'] ?? 'Student';
            _regId = data['studentId'] ?? 'N/A';
            _dept = data['department'] ?? 'CS';
            _program = data['program'] ?? 'BS';
            _isFetchingProfile = false;

            // Generate STATIC QR (No Timestamp)
            _qrData = "${widget.eventData['id']}|$_userId";
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isFetchingProfile = false);
    }
  }

  // --- PRIVACY LOGIC ---
  Future<void> _secureScreen() async {
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageWithBlur();
  }

  Future<void> _unsecureScreen() async {
    await ScreenProtector.preventScreenshotOff();
    await ScreenProtector.protectDataLeakageWithBlurOff();
  }

  @override
  void dispose() {
    _unsecureScreen();
    super.dispose();
  }

  // --- LOGIC: REGISTER & AUTO NAVIGATE ---
  Future<void> _processPaymentAndRegister() async {
    setState(() => _isLoading = true);

    try {
      // 1. Update Firestore
      await FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']).update({
        'registeredStudents': FieldValue.arrayUnion([_userId])
      });

      // 2. Show Success Step
      setState(() {
        _isLoading = false;
        _currentStep = 3;
      });

      // 3. Auto Navigate after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          Navigator.pop(context); // Go back to Dashboard
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registration Completed!"), backgroundColor: Colors.green));
        }
      });

    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: theme.iconTheme.color),
        title: Text(
            _currentStep == 3 ? "Ticket Generated" : "Registration",
            style: theme.textTheme.headlineMedium
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),

          SafeArea(
            child: Column(
              children: [
                if (_currentStep < 3) _buildStepIndicator(theme),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _isFetchingProfile
                        ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                        : _buildCurrentStep(theme, isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP SWITCHER ---
  Widget _buildCurrentStep(ThemeData theme, bool isDark) {
    switch (_currentStep) {
      case 1: return _buildStep1Verification(theme);
      case 2: return _buildStep2Payment(theme, isDark);
      case 3: return _buildStep3Success(theme, isDark);
      default: return Container();
    }
  }

  // --- STEP 1: VERIFICATION ---
  Widget _buildStep1Verification(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Step 1: Verify Details", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor)),
        const SizedBox(height: 8),
        Text("Please ensure your profile information is correct.", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              CircleAvatar(radius: 40, backgroundColor: theme.primaryColor.withOpacity(0.1), child: Icon(Icons.person, size: 40, color: theme.primaryColor)),
              const SizedBox(height: 16),
              _buildDetailRow("Name", _name, theme),
              const Divider(),
              _buildDetailRow("Reg ID", _regId, theme),
              const Divider(),
              _buildDetailRow("Department", _dept, theme),
              const Divider(),
              _buildDetailRow("Program", _program, theme),
            ],
          ),
        ),

        const SizedBox(height: 30),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: Colors.red.withOpacity(0.7)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Update Profile", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() => _currentStep = 2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Next", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- STEP 2: PAYMENT ---
  Widget _buildStep2Payment(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Step 2: Payment", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor)),
        const SizedBox(height: 8),
        Text("Pay registration fee to proceed.", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Total Fee", style: TextStyle(color: theme.primaryColor, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text("PKR ${widget.eventData['fee']}", style: theme.textTheme.headlineSmall?.copyWith(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 22)),
                ],
              ),
              Icon(Icons.receipt_long, color: theme.primaryColor, size: 30),
            ],
          ),
        ),

        const SizedBox(height: 24),
        Text("Select Payment Method", style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        _buildPaymentMethodTile("Easypaisa", Icons.account_balance_wallet, true, theme),
        const SizedBox(height: 10),
        _buildPaymentMethodTile("Pay at Desk", Icons.store, false, theme),

        const SizedBox(height: 40),

        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _processPaymentAndRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Pay Now & Confirm", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // --- STEP 3: SUCCESS & STATIC QR ---
  Widget _buildStep3Success(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircleAvatar(
          radius: 35,
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 16),
        Text("Success!", style: theme.textTheme.headlineLarge?.copyWith(color: Colors.green)),
        const SizedBox(height: 8),
        Text("Redirecting to Dashboard...", style: theme.textTheme.bodyMedium),

        const SizedBox(height: 30),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
          ),
          child: Column(
            children: [
              // STATIC QR CODE (No Refreshing)
              QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              const SizedBox(height: 10),
              Text("Ticket ID: ${widget.eventData['id'].toString().substring(0, 5).toUpperCase()}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        const SizedBox(height: 40),
        const CircularProgressIndicator(), // Loading indicator to show redirection is happening
      ],
    );
  }

  // --- HELPER WIDGETS ---

  // FIXED: ADDED EXPANDED TO PREVENT OVERFLOW
  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align to top for multi-line text
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 16), // Spacing
          Expanded( // Ensures text wraps and doesn't overflow
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodTile(String name, IconData icon, bool isSelected, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isSelected ? theme.primaryColor.withOpacity(0.1) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? theme.primaryColor : theme.dividerColor, width: isSelected ? 2 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: isSelected ? theme.primaryColor : Colors.grey),
          const SizedBox(width: 16),
          Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          if (isSelected) Icon(Icons.check_circle, color: theme.primaryColor, size: 20),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepCircle(1, "Verify", theme),
          _buildLine(theme),
          _buildStepCircle(2, "Payment", theme),
          _buildLine(theme),
          _buildStepCircle(3, "Ticket", theme),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label, ThemeData theme) {
    bool isActive = _currentStep >= step;
    return Column(
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: isActive ? theme.primaryColor : Colors.grey.withOpacity(0.3),
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 10)] : [],
          ),
          child: Center(
            child: isActive
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text("$step", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold))
      ],
    );
  }

  Widget _buildLine(ThemeData theme) {
    return Container(
      width: 40, height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      color: Colors.grey.withOpacity(0.3),
    );
  }
}
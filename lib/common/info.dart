import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Auth Import
import 'package:cloud_firestore/cloud_firestore.dart'; // Database Import
import '../theme/theme.dart';
import 'login.dart';
import '../student/student_dashboard.dart'; // IMPORTANT: Dashboard Import for Auto-Navigation

class InfoScreen extends StatefulWidget {
  final String email;

  const InfoScreen({super.key, required this.email});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _studentIdController = TextEditingController(); // SAP ID (Auto-filled)
  final TextEditingController _phoneController = TextEditingController();

  // Focus Nodes
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  String? _focusedField;

  // Dropdown Values
  String? _selectedDepartment; // Main Department Logic
  String? _selectedProgram;
  String? _selectedField; // [NEW: Field Variable]
  String? _selectedSemester;
  String? _selectedSection;

  // State
  bool _isLoading = false;

  // --- DATA LISTS ---
  // 1. Departments (Jo aapne provide kiye)
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

  final List<String> _programs = ['BS', 'MS', 'PhD'];

  // [NEW: Field List added]
  final List<String> _fields = ['CS', 'SE', 'IT', 'AI', 'DS', 'CEN', 'EE', 'BBA', 'General'];

  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  final List<String> _sections = ['A', 'B', 'C', 'D', 'E', 'F', 'Morning', 'Evening'];

  late AnimationController _blobController;

  @override
  void initState() {
    super.initState();

    // --- AUTO SAP ID LOGIC ---
    // Email: 70159060@student.uol.edu.pk -> SAP ID: 70159060
    String email = widget.email;
    if (email.contains('@')) {
      String extractedId = email.split('@')[0];
      _studentIdController.text = extractedId; // Auto-fill
    }

    // Animation Controller
    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    _nameFocus.addListener(() { setState(() => _focusedField = _nameFocus.hasFocus ? 'name' : null); });
    _phoneFocus.addListener(() { setState(() => _focusedField = _phoneFocus.hasFocus ? 'phone' : null); });
  }

  @override
  void dispose() {
    _nameController.dispose(); _studentIdController.dispose(); _phoneController.dispose();
    _nameFocus.dispose(); _phoneFocus.dispose();
    _blobController.dispose();
    super.dispose();
  }

  // --- ENSURE DEPARTMENT EXISTS ---
  Future<void> _ensureDepartmentExists(String deptName) async {
    final deptRef = FirebaseFirestore.instance.collection('departments').doc(deptName);
    final doc = await deptRef.get();

    if (!doc.exists) {
      await deptRef.set({
        'name': deptName,
        'isLocked': false, // Default Open
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // --- MAIN LOGIC: SAVE & SEND FOR VERIFICATION ---
  Future<void> _handleCompleteProfile() async {
    // 1. Basic Validation
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
      _showSnackBar("Please fill all text fields", Colors.red);
      return;
    }

    // [UPDATED] Check _selectedField as well
    if (_selectedDepartment == null || _selectedProgram == null || _selectedField == null || _selectedSemester == null || _selectedSection == null) {
      _showSnackBar("Please select Department and all Class details", Colors.orange);
      return;
    }

    String pattern = r'^((\+92)?(0092)?(92)?(0)?)(3)([0-9]{9})$';
    RegExp regExp = RegExp(pattern);
    if (!regExp.hasMatch(_phoneController.text)) {
      _showSnackBar("Invalid Phone. Use format 03XXXXXXXXX", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No user found. Please login again.");

      // 2. Prepare Data
      Map<String, dynamic> userData = {
        'uid': user.uid,
        'email': widget.email,
        'fullName': _nameController.text.trim(),
        'sapId': _studentIdController.text.trim(), // Auto-filled ID
        'department': _selectedDepartment, // Selected Department
        'program': _selectedProgram,
        'field': _selectedField, // [NEW: Saving Field]
        'semester': _selectedSemester,
        'section': _selectedSection,
        'phone': _phoneController.text.trim(),
        'role': 'student',
        'isProfileComplete': true,
        'status': 'pending', // IMPORTANT: Pending for Admin Verification
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 3. Save to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));

      // 4. Ensure Department Exists in DB
      await _ensureDepartmentExists(_selectedDepartment!);

      if (!mounted) return;

      // 5. Redirect to Verification Waiting Screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const VerificationPendingScreen()),
            (route) => false,
      );

    } catch (e) {
      _showSnackBar("Error saving profile: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(brightness)),
            ),
          ),
          _buildAnimatedBlob(top: size.height * 0.1, right: -50, color: theme.primaryColor.withOpacity(0.15), size: 250, scaleOffset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -50, color: AppTheme.uolSecondary.withOpacity(0.15), size: 250, scaleOffset: 0.7),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]),
                    child: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]).createShader(bounds),
                    child: Text("Complete Profile", style: theme.textTheme.headlineLarge?.copyWith(fontSize: 28, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 4),
                  Text("Enter details for Admin Verification", style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Account Email", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          width: double.infinity,
                          decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: theme.primaryColor.withOpacity(0.2))),
                          child: Row(
                            children: [
                              Icon(Icons.email_outlined, size: 18, color: theme.primaryColor),
                              const SizedBox(width: 10),
                              Expanded(child: Text(widget.email, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: theme.primaryColor), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // --- SAP ID (READ ONLY) ---
                        Text("SAP ID (Auto-filled)", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        // Note: Using a disabled TextField to show it's read-only
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: theme.inputDecorationTheme.fillColor?.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.withOpacity(0.5))
                          ),
                          child: TextField(
                            controller: _studentIdController,
                            enabled: false, // User CANNOT edit this
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey),
                            decoration: const InputDecoration(
                                border: InputBorder.none,
                                icon: Icon(Icons.badge, color: Colors.grey)
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Text("Full Name", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        _buildThemeInputField(controller: _nameController, focusNode: _nameFocus, icon: Icons.person_outline, hint: "Your Full Name", isFocused: _focusedField == 'name', theme: theme),

                        const SizedBox(height: 16),

                        // --- DEPARTMENT DROPDOWN ---
                        Text("Department", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        _buildThemeDropdown(
                            value: _selectedDepartment,
                            items: _departments,
                            hint: "Select Department",
                            icon: Icons.apartment,
                            theme: theme,
                            onChanged: (val) => setState(() => _selectedDepartment = val)
                        ),

                        const SizedBox(height: 16),
                        // --- ROW 1: Program & Field ---
                        Row(
                          children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Program", style: theme.textTheme.labelMedium), const SizedBox(height: 6), _buildThemeDropdown(value: _selectedProgram, items: _programs, hint: "BS", icon: Icons.school_outlined, theme: theme, onChanged: (val) => setState(() => _selectedProgram = val))])),
                            const SizedBox(width: 12),
                            // [NEW FIELD DROPDOWN]
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Field", style: theme.textTheme.labelMedium), const SizedBox(height: 6), _buildThemeDropdown(value: _selectedField, items: _fields, hint: "CS/SE", icon: Icons.category_outlined, theme: theme, onChanged: (val) => setState(() => _selectedField = val))])),
                          ],
                        ),

                        const SizedBox(height: 16),
                        // --- ROW 2: Semester & Section ---
                        Row(
                          children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Semester", style: theme.textTheme.labelMedium), const SizedBox(height: 6), _buildThemeDropdown(value: _selectedSemester, items: _semesters, hint: "1", icon: Icons.timeline, theme: theme, onChanged: (val) => setState(() => _selectedSemester = val))])),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Section", style: theme.textTheme.labelMedium), const SizedBox(height: 6), _buildThemeDropdown(value: _selectedSection, items: _sections, hint: "A", icon: Icons.class_outlined, theme: theme, onChanged: (val) => setState(() => _selectedSection = val))])),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Text("Phone Number", style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        _buildThemeInputField(controller: _phoneController, focusNode: _phoneFocus, icon: Icons.phone_android, hint: "03XXXXXXXXX", isFocused: _focusedField == 'phone', theme: theme),

                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity, height: 48,
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isLoading ? null : _handleCompleteProfile,
                              borderRadius: BorderRadius.circular(12),
                              child: Center(child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Submit for Verification", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.check_circle_outline, color: Colors.white, size: 18)])),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeInputField({required TextEditingController controller, required FocusNode focusNode, required IconData icon, required String hint, required bool isFocused, required ThemeData theme}) {
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
          Expanded(child: TextField(controller: controller, focusNode: focusNode, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14), decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, hintText: hint, hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(fontSize: 13), isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 14)))),
        ],
      ),
    );
  }

  Widget _buildThemeDropdown({required String? value, required List<String> items, required String hint, required IconData icon, required ThemeData theme, required Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(color: theme.inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color)),
      child: Row(
        children: [
          Icon(icon, color: theme.iconTheme.color?.withOpacity(0.5), size: 18),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(hint, style: theme.inputDecorationTheme.hintStyle?.copyWith(fontSize: 13)),
              icon: Icon(Icons.keyboard_arrow_down, size: 20, color: theme.primaryColor),
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              dropdownColor: theme.cardColor,
              items: items.map((String item) {return DropdownMenuItem<String>(value: item, child: Text(item));}).toList(),
              onChanged: onChanged
          ))),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top, double? left, double? right, double? bottom,
    required Color color, required double size, required double scaleOffset
  }) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (_, __) => Transform.scale(
          scale: 1.0 + (sin(_blobController.value * 2 * pi + scaleOffset) * 0.2),
          child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])),
        ),
      ),
    );
  }
}

// --- VERIFICATION PENDING SCREEN (UNCHANGED LOGIC) ---
class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen> {
  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          String status = snapshot.data()?['status'] ?? 'pending';
          // Check if Approved
          if ((status == 'active' || status == 'approved') && mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => StudentDashboard(userEmail: user.email!)),
                  (route) => false,
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 60, color: Colors.orange),
                  const SizedBox(height: 20),
                  Text("Verification Pending", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
                  const SizedBox(height: 16),
                  Text(
                    "Your profile is under review by your Department Admin.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      "Note: You cannot access the app until your admin approves your request.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const CircularProgressIndicator(color: Colors.orange),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if(context.mounted) {
                          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                      label: const Text("Logout & Check Later", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
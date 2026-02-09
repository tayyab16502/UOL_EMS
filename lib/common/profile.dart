import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/theme.dart';
import '../theme/theme_manager.dart'; // Theme Manager
import 'login.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  // Logic Variables
  bool _isEditing = false;
  bool _isLoading = true;
  String _currentCollection = 'users'; // Used for UI Title
  String _role = 'student';
  late DocumentReference _userDocRef;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Data Variables
  String _email = "";
  String _regId = "";
  String _department = "";

  // Dropdown Values
  String _selectedProgram = 'BS';
  String _selectedField = 'CS';
  String _selectedSemester = '1';
  String? _selectedSection = 'A';

  // Lists
  final List<String> _programs = ['BS', 'MS', 'PhD'];
  final List<String> _fields = ['CS', 'SE', 'AI', 'IT'];
  final List<String> _semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
  final List<String> _sections = ['A', 'B', 'C', 'D', 'E', 'F'];

  late AnimationController _blobController;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _blobController.dispose();
    super.dispose();
  }

  // --- 1. FETCH DATA (FLAT STRUCTURE UPDATE) ---
  Future<void> _fetchUserData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // [FLAT STRUCTURE] Direct lookup in 'users' collection
      _userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      DocumentSnapshot doc = await _userDocRef.get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        if (mounted) {
          setState(() {
            // Identify Role
            _role = data['role'] ?? 'student';

            // Set Collection String for UI Title (Admin Profile vs Student Profile)
            _currentCollection = (_role == 'admin') ? 'admins' : 'users';

            // Populate Basic Info
            _nameController.text = data['fullName'] ?? 'User';
            _phoneController.text = data['phone'] ?? '';
            _email = data['email'] ?? user.email ?? "";

            // Handle Department & ID
            _department = data['department'] ?? 'General';
            _regId = data['sapId'] ?? data['studentId'] ?? 'N/A';

            // Populate Academic Dropdowns (Only valid for Students)
            if (_role == 'student') {
              if (_programs.contains(data['program'])) _selectedProgram = data['program'];
              if (_fields.contains(data['field'])) _selectedField = data['field'];
              if (_semesters.contains(data['semester'])) _selectedSemester = data['semester'];
              if (_sections.contains(data['section'])) _selectedSection = data['section'];
            } else {
              // For Admins/Guards
              _selectedProgram = 'N/A';
              _selectedField = 'N/A';
              _selectedSemester = 'N/A';
              _selectedSection = 'N/A';
              _regId = 'ADMIN';
            }

            // Sync Theme Preference
            if (data.containsKey('isDarkMode')) {
              bool dbIsDark = data['isDarkMode'] as bool;
              if (themeManager.isDarkMode != dbIsDark) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  themeManager.toggleTheme(dbIsDark);
                });
              }
            }

            _isLoading = false;
          });
        }
      } else {
        // Doc doesn't exist
        debugPrint("User document not found in 'users' collection.");
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar("Error fetching profile", Colors.red);
      }
    }
  }

  // --- 2. UPDATE DATA ---
  Future<void> _saveProfileChanges() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> updates = {
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };

      // Only update academic fields for students
      if (_role == 'student') {
        updates.addAll({
          'program': _selectedProgram,
          'field': _selectedField,
          'semester': _selectedSemester,
          'section': _selectedSection,
        });
      }

      await _userDocRef.update(updates);
      _showSnackBar("Profile Updated!", Colors.green);
    } catch (e) {
      debugPrint("Update error: $e");
      _showSnackBar("Update Failed", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 3. SAVE THEME PREFERENCE ---
  Future<void> _updateThemePreference(bool isDark) async {
    try {
      await _userDocRef.set(
        {'isDarkMode': isDark},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint("Failed to save theme: $e");
    }
  }

  void _toggleEdit() {
    if (_isEditing) {
      _saveProfileChanges();
    }
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  // --- 4. LOGOUT ---
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Logout?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- 5. DELETE ACCOUNT ---
  void _handleDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text("Delete Account?", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure? This will remove your data permanently.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performDeletion();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeletion() async {
    setState(() => _isLoading = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _userDocRef.delete(); // Delete Firestore Doc
        await user.delete();        // Delete Auth User

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
          );
          _showSnackBar("Account Deleted.", Colors.grey);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar("Re-login required to delete account.", Colors.red);
      }
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    bool isDarkMode = themeManager.isDarkMode;

    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.getGradient(theme.brightness),
            ),
          ),
          child: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        title: Text(
          _currentCollection == 'admins' ? "Admin Profile" : "Profile",
          style: theme.textTheme.headlineMedium,
        ),
        centerTitle: true,
        actions: [
          Row(
            children: [
              Icon(
                isDarkMode ? Icons.dark_mode : Icons.light_mode,
                size: 18,
                color: theme.iconTheme.color,
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: isDarkMode,
                  activeColor: theme.primaryColor,
                  onChanged: (value) {
                    themeManager.toggleTheme(value);
                    _updateThemePreference(value);
                  },
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              _isEditing ? Icons.check : Icons.edit,
              color: _isEditing ? Colors.green : theme.iconTheme.color,
            ),
            onPressed: _toggleEdit,
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppTheme.getGradient(theme.brightness),
              ),
            ),
          ),
          _buildAnimatedBlob(
            top: size.height * 0.1,
            right: -100,
            color: theme.primaryColor.withOpacity(0.15),
            size: 300,
            offset: 0.2,
          ),
          _buildAnimatedBlob(
            bottom: size.height * 0.1,
            left: -100,
            color: AppTheme.uolSecondary.withOpacity(0.15),
            size: 300,
            offset: 0.7,
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  // HEADER
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.primaryColor, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          child: Icon(Icons.person, size: 40, color: theme.iconTheme.color),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _isEditing
                                ? TextField(
                              controller: _nameController,
                              style: theme.textTheme.headlineSmall,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                hintText: "Enter Name",
                              ),
                            )
                                : Text(_nameController.text, style: theme.textTheme.headlineSmall),
                            Text(
                              _email,
                              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "ID: $_regId",
                                style: TextStyle(
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),
                  const Divider(),
                  const SizedBox(height: 5),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Academic Details", style: theme.textTheme.labelMedium),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile("Dept", _department, Icons.apartment, theme, isEditable: false),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildInfoTile(
                          "Program",
                          _selectedProgram,
                          Icons.school,
                          theme,
                          isEditable: _isEditing && _role == 'student',
                          isDropdown: true,
                          items: _programs,
                          onChanged: (v) => setState(() => _selectedProgram = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          "Field",
                          _selectedField,
                          Icons.computer,
                          theme,
                          isEditable: _isEditing && _role == 'student',
                          isDropdown: true,
                          items: _fields,
                          onChanged: (v) => setState(() => _selectedField = v!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildInfoTile(
                          "Semester",
                          _selectedSemester,
                          Icons.timeline,
                          theme,
                          isEditable: _isEditing && _role == 'student',
                          isDropdown: true,
                          items: _semesters,
                          onChanged: (v) => setState(() => _selectedSemester = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoTile(
                          "Section",
                          _selectedSection ?? "-",
                          Icons.class_,
                          theme,
                          isEditable: _isEditing && _role == 'student',
                          isDropdown: true,
                          items: _sections,
                          onChanged: (v) => setState(() => _selectedSection = v!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.phone, size: 14, color: theme.hintColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Phone",
                                    style: TextStyle(fontSize: 10, color: theme.hintColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _isEditing
                                  ? SizedBox(
                                height: 20,
                                child: TextField(
                                  controller: _phoneController,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              )
                                  : Text(
                                _phoneController.text.isEmpty ? "Not set" : _phoneController.text,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // LOGOUT + DELETE
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _handleLogout,
                          icon: Icon(Icons.logout, size: 18, color: theme.primaryColor),
                          label: Text("Logout", style: TextStyle(color: theme.primaryColor)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: theme.primaryColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _handleDeleteAccount,
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white),
                          label: const Text("Delete", style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  Column(
                    children: [
                      Text(
                        "About Developers",
                        style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildDevAvatar(theme, "Tayyab Khan"),
                          const SizedBox(width: 25),
                          _buildDevAvatar(theme, "Shomail Khan"),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevAvatar(ThemeData theme, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.primaryColor.withOpacity(0.5), width: 2),
            boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: theme.cardColor,
            child: Icon(Icons.person_outline, size: 30, color: theme.primaryColor),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildInfoTile(
      String title,
      String value,
      IconData icon,
      ThemeData theme, {
        bool isEditable = false,
        bool isDropdown = false,
        List<String>? items,
        Function(String?)? onChanged,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isEditable ? theme.primaryColor.withOpacity(0.5) : theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.hintColor),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 10, color: theme.hintColor)),
            ],
          ),
          const SizedBox(height: 4),
          if (isEditable && isDropdown)
            SizedBox(
              height: 20,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  icon: Icon(Icons.arrow_drop_down, size: 18, color: theme.primaryColor),
                  dropdownColor: theme.cardColor,
                  items: items!
                      .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ))
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            )
          else
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    required double size,
    required Color color,
    required double offset,
    double? top,
    double? left,
    double? right,
    double? bottom,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (_, __) => Transform.scale(
          scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 100)],
            ),
          ),
        ),
      ),
    );
  }
}
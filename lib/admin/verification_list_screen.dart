import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/theme.dart';

class VerificationListScreen extends StatefulWidget {
  const VerificationListScreen({super.key});

  @override
  State<VerificationListScreen> createState() => _VerificationListScreenState();
}

class _VerificationListScreenState extends State<VerificationListScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blobController;

  // --- STATE VARIABLES ---
  String? _adminDept; // Store current admin's dept
  String? _adminName; // Store current admin's Name (Added for Stamp)
  bool _isLoadingContext = true; // To handle loading state safely

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _getAdminContext();
  }

  // --- UPDATED: FETCH ADMIN CONTEXT (Name & Dept) ---
  void _getAdminContext() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          if (mounted) {
            setState(() {
              // Get the department field
              _adminDept = userDoc.get('department');

              // Get the Full Name for "Approved By" Stamp
              // (Try catch block just in case field missing ho)
              try {
                _adminName = userDoc.get('fullName');
              } catch (e) {
                _adminName = "Admin";
              }

              _isLoadingContext = false; // Stop Loading
            });
          }
        } else {
          debugPrint("Admin document not found in 'users' collection.");
          if (mounted) setState(() => _isLoadingContext = false);
        }
      }
    } catch (e) {
      debugPrint("Error fetching admin context: $e");
      if (mounted) setState(() => _isLoadingContext = false);
    }
  }

  @override
  void dispose() {
    _blobController.dispose();
    super.dispose();
  }

  // --- UPDATED: VERIFY LOGIC (WITH STAMP) ---
  void _verifyStudent(String uid, String name) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'status': 'approved', // Login logic requires 'approved'
        'isApproved': true,   // Backup boolean
        'approvedBy': _adminName ?? 'System', // <--- STAMP ADDED HERE
        'approvedAt': FieldValue.serverTimestamp(), // Optional: Time of approval
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$name Verified by ${_adminName ?? 'Admin'}!"),
                backgroundColor: Colors.green
            )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _rejectStudent(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'status': 'blocked'});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User Blocked"), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // --- Loading State ---
    if (_isLoadingContext) {
      return Scaffold(
        body: Stack(
          children: [
            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
            Center(child: CircularProgressIndicator(color: theme.primaryColor)),
          ],
        ),
      );
    }

    // Check if Department found
    if (_adminDept == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: const BackButton()),
        body: const Center(child: Text("Error: Admin Department not found.\nPlease check your account permissions.")),
      );
    }

    // Normalize String
    String currentDept = _adminDept!.trim();
    bool isSuperAdmin = currentDept == 'Computer Science' || currentDept == 'CS';

    // Query Logic:
    // Students are now in 'users' collection with status 'pending'
    Query query = FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending');

    // If NOT Super Admin, only show students from MY department
    if (!isSuperAdmin) {
      query = query.where('department', isEqualTo: currentDept);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
          title: const Text("Pending Approvals"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: const BackButton()
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0),
          _buildBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.5),

          StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
                          const SizedBox(height: 10),
                          Text("All caught up!", style: theme.textTheme.headlineSmall),
                          if(!isSuperAdmin) Text("No pending requests for $_adminDept", style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey))
                        ]
                    )
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 100, 16, 20),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var doc = snapshot.data!.docs[index];
                  var data = doc.data() as Map<String, dynamic>;

                  String name = data['fullName'] ?? 'Unknown';
                  // Prefer SAP ID, fallback to Student ID
                  String studentId = data['sapId'] ?? data['studentId'] ?? 'N/A';
                  String phone = data['phone'] ?? 'N/A';
                  String program = data['program'] ?? 'N/A';
                  String field = data['field'] ?? 'N/A';
                  String semester = data['semester'] ?? 'N/A';
                  String section = data['section'] ?? 'N/A';
                  String department = data['department'] ?? 'CS';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.cardColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.all(12),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.orange.withOpacity(0.1),
                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 20)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text("$studentId  •  $department", style: TextStyle(color: theme.primaryColor, fontSize: 12)),
                          children: [
                            const Divider(),
                            _buildDetailRow("Phone", phone, Icons.phone),
                            _buildDetailRow("Department", department, Icons.apartment),
                            const SizedBox(height: 8),
                            Row(children: [Expanded(child: _buildDetailBox("Program", program, theme)), const SizedBox(width: 8), Expanded(child: _buildDetailBox("Field", field, theme))]),
                            const SizedBox(height: 8),
                            Row(children: [Expanded(child: _buildDetailBox("Semester", semester, theme)), const SizedBox(width: 8), Expanded(child: _buildDetailBox("Section", section, theme))]),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(child: OutlinedButton.icon(onPressed: () => _rejectStudent(doc.id), icon: const Icon(Icons.close, color: Colors.red, size: 18), label: const Text("Reject", style: TextStyle(color: Colors.red)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)))),
                                const SizedBox(width: 12),
                                Expanded(child: ElevatedButton.icon(onPressed: () => _verifyStudent(doc.id, name), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), icon: const Icon(Icons.check, color: Colors.white, size: 18), label: const Text("Approve", style: TextStyle(color: Colors.white)))),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 10), Text("$label: ", style: const TextStyle(fontSize: 13, color: Colors.grey)), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))],
      ),
    );
  }

  Widget _buildDetailBox(String label, String value, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: theme.canvasColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.dividerColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, color: theme.hintColor)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
    );
  }

  Widget _buildBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
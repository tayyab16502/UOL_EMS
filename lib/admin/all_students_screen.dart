import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/theme.dart';

class AllStudentsScreen extends StatefulWidget {
  const AllStudentsScreen({super.key});

  @override
  State<AllStudentsScreen> createState() => _AllStudentsScreenState();
}

class _AllStudentsScreenState extends State<AllStudentsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blobController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String? _adminDept;
  bool _isLoadingContext = true; // NEW: To handle initial loading state

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _getAdminContext();
  }

  // --- FETCH ADMIN CONTEXT (UPDATED: FLAT STRUCTURE) ---
  void _getAdminContext() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // [FLAT STRUCTURE]
        // Instead of searching nested 'admin' collections, search 'users' directly
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          if (mounted) {
            setState(() {
              // Get the department field from the Admin's profile
              _adminDept = userDoc.get('department');
              _isLoadingContext = false;
            });
          }
        } else {
          // If admin doc not found
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
    _searchController.dispose();
    super.dispose();
  }

  // --- SORTING HELPERS (UNCHANGED) ---
  int getFieldPriority(String field) {
    String f = field.toUpperCase().trim();
    if (f == 'AI') return 0;
    if (f == 'CS') return 1;
    if (f == 'IT') return 2;
    if (f == 'SE') return 3;
    return 4;
  }

  int _parseSemester(String? sem) {
    if (sem == null) return 0;
    String digits = sem.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  String _getGroupLabel(Map<String, dynamic> data) {
    String p = data['program'] ?? '';
    String f = data['field'] ?? '';
    String s = data['semester'] ?? '';
    String sec = data['section'] ?? '';
    if (p.isEmpty && f.isEmpty) return "Unassigned Class";
    return "$p-$f-$s$sec".toUpperCase();
  }

  // --- [NEW LOGIC] TOGGLE MANAGER STATUS ---
  Future<void> _toggleManagerStatus(String uid, bool currentStatus, String name) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isManager': !currentStatus,
      });

      String msg = !currentStatus
          ? "$name promoted to Class Manager!"
          : "$name removed from Manager.";

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: !currentStatus ? Colors.green : Colors.orange
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  // --- GROUPING LOGIC (UNCHANGED) ---
  Map<String, List<DocumentSnapshot>> _groupStudents(List<DocumentSnapshot> docs) {
    List<DocumentSnapshot> filtered = docs.where((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String name = (data['fullName'] ?? '').toString().toLowerCase();
      String id = (data['studentId'] ?? data['sapId'] ?? '').toString().toLowerCase();
      String classStr = _getGroupLabel(data).toLowerCase();
      String query = _searchQuery.toLowerCase();

      // Filter by Search Query
      return name.contains(query) || id.contains(query) || classStr.contains(query);
    }).toList();

    // Sort
    filtered.sort((a, b) {
      Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
      Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
      int semA = _parseSemester(dataA['semester']);
      int semB = _parseSemester(dataB['semester']);
      if (semA != semB) return semB.compareTo(semA); // Descending Semester

      int fieldA = getFieldPriority(dataA['field'] ?? '');
      int fieldB = getFieldPriority(dataB['field'] ?? '');
      if (fieldA != fieldB) return fieldA.compareTo(fieldB);

      String secA = (dataA['section'] ?? '').toString();
      String secB = (dataB['section'] ?? '').toString();
      return secA.compareTo(secB);
    });

    // Group
    Map<String, List<DocumentSnapshot>> groups = {};
    for (var doc in filtered) {
      String label = _getGroupLabel(doc.data() as Map<String, dynamic>);
      if (!groups.containsKey(label)) {
        groups[label] = [];
      }
      groups[label]!.add(doc);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Show Loading while fetching admin details
    if (_isLoadingContext) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: theme.primaryColor)));
    }

    // Normalize Dept String
    String currentDept = (_adminDept ?? '').trim();
    bool isSuperAdmin = currentDept == 'Computer Science' || currentDept == 'CS';

    // --- QUERY CONSTRUCTION (FLAT STRUCTURE) ---
    // Look for users where role is 'student'
    Query query = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');

    // If NOT Super Admin, filter by department
    if (!isSuperAdmin && _adminDept != null) {
      query = query.where('department', isEqualTo: currentDept);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Student Directory"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(),
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildBlob(top: size.height * 0.1, left: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0),
          _buildBlob(bottom: size.height * 0.1, right: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.5),

          Column(
            children: [
              SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  style: theme.textTheme.bodyMedium,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: "Search Name, SAP ID, or Class...",
                    hintStyle: TextStyle(color: theme.hintColor.withOpacity(0.6)),
                    prefixIcon: Icon(Icons.search, color: theme.primaryColor),
                    filled: true,
                    fillColor: theme.cardColor.withOpacity(0.8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                  ),
                ),
              ),

              // Student List
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    // 1. Loading State
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: theme.primaryColor));
                    }

                    // 2. Error State
                    if (snapshot.hasError) {
                      return Center(child: Text("Error loading data.", style: TextStyle(color: Colors.red)));
                    }

                    // 3. Empty State (No Students found in DB)
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_outlined, size: 60, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 10),
                            Text("No Active Students Found", style: theme.textTheme.headlineSmall?.copyWith(color: Colors.grey)),
                            if (!isSuperAdmin)
                              Text("in $_adminDept Department", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      );
                    }

                    // 4. Data Found - Process & Group
                    Map<String, List<DocumentSnapshot>> groupedStudents = _groupStudents(snapshot.data!.docs);

                    // 5. Empty State (Search Filter returned nothing)
                    if (groupedStudents.isEmpty) {
                      return Center(child: Text("No matches found for '$_searchQuery'", style: theme.textTheme.bodyMedium));
                    }

                    // 6. Render List
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      itemCount: groupedStudents.length,
                      itemBuilder: (context, index) {
                        String key = groupedStudents.keys.elementAt(index);
                        List<DocumentSnapshot> students = groupedStudents[key]!;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.cardColor.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              iconColor: theme.primaryColor,
                              collapsedIconColor: theme.hintColor,
                              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                  key, // Class Name e.g. BS-CS-8A
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: theme.primaryColor
                                  )
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: theme.primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12)
                                    ),
                                    child: Text("${students.length}", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.keyboard_arrow_down),
                                ],
                              ),
                              children: students.map((doc) => _buildStudentCard(doc, theme)).toList(),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- STUDENT CARD WIDGET (UPDATED) ---
  Widget _buildStudentCard(DocumentSnapshot doc, ThemeData theme) {
    var data = doc.data() as Map<String, dynamic>;
    String name = data['fullName'] ?? 'Unknown';
    // Use SAP ID first, fall back to Student ID
    String sapId = data['sapId'] ?? data['studentId'] ?? 'N/A';
    String phone = data['phone'] ?? 'N/A';

    // Class Info
    String program = data['program'] ?? '-';
    String field = data['field'] ?? '-';
    String semester = data['semester'] ?? '-';
    String section = data['section'] ?? '-';

    String status = data['status'] ?? 'active';
    bool isActive = status == 'active';

    // --- [NEW LOGIC VARIABLES] ---
    bool isManager = data['isManager'] ?? false;
    String approvedBy = data['approvedBy'] ?? 'System';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        // [VISUAL UPDATE] Orange border for Managers
        border: Border.all(color: isManager ? Colors.orange : theme.dividerColor, width: isManager ? 1.5 : 1),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: CircleAvatar(
          radius: 18,
          // [VISUAL UPDATE] Star icon for Managers
          backgroundColor: isManager ? Colors.orange.withOpacity(0.2) : (isActive ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
          child: Icon(isManager ? Icons.star : Icons.person, color: isManager ? Colors.orange : (isActive ? Colors.green : Colors.orange), size: 18),
        ),
        title: Row(
          children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            // [VISUAL UPDATE] Manager Badge
            if (isManager) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text("MANAGER", style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ]
          ],
        ),
        subtitle: Text("SAP: $sapId", style: TextStyle(fontSize: 12, color: theme.hintColor)),

        // [NEW FEATURE] 3-Dots Menu for Manager Toggle
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: theme.iconTheme.color),
              onSelected: (val) {
                if (val == 'toggle_manager') {
                  _toggleManagerStatus(doc.id, isManager, name);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_manager',
                  child: Row(
                    children: [
                      Icon(isManager ? Icons.person_off : Icons.star, color: isManager ? Colors.red : Colors.orange, size: 18),
                      const SizedBox(width: 10),
                      Text(isManager ? "Remove Manager" : "Make Manager"),
                    ],
                  ),
                ),
              ],
            ),
            const Icon(Icons.keyboard_arrow_down, size: 18), // Keep expansion hint
          ],
        ),

        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          const Divider(height: 10),
          _buildDetailRow("Phone", phone, Icons.phone_android),
          _buildDetailRow(
              "Status",
              status.toUpperCase(),
              isActive ? Icons.check_circle : Icons.warning_amber,
              color: isActive ? Colors.green : Colors.orange
          ),

          const SizedBox(height: 4),

          // [NEW FEATURE] APPROVED BY STAMP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.withOpacity(0.3))
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 12, color: Colors.green),
                const SizedBox(width: 6),
                Text("Approved by: $approvedBy", style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Class Tags
          Row(
            children: [
              Expanded(child: _buildDetailBox("Prog", program, theme)),
              const SizedBox(width: 4),
              Expanded(child: _buildDetailBox("Field", field, theme)),
              const SizedBox(width: 4),
              Expanded(child: _buildDetailBox("Sem", semester, theme)),
              const SizedBox(width: 4),
              Expanded(child: _buildDetailBox("Sec", section, theme)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color))),
        ],
      ),
    );
  }

  Widget _buildDetailBox(String label, String value, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.dividerColor.withOpacity(0.5))
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 8, color: theme.hintColor)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)
        ],
      ),
    );
  }

  Widget _buildBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: AnimatedBuilder(
        animation: _blobController,
        builder: (_, __) => Transform.scale(
            scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2),
            child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)]))
        ),
      ),
    );
  }
}
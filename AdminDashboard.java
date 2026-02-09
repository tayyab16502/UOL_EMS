import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/theme.dart';
import '../common/profile.dart';
import 'create_event.dart';
import 'manage_event.dart';
import '../guard/scan_ticket.dart';
import 'verification_list_screen.dart';
import 'department_control_screen.dart';
// Note: 'all_students_screen.dart' import hata diya kyunke ab list yehi par hai.

class AdminDashboard extends StatefulWidget {
  final String userEmail;
  const AdminDashboard({super.key, required this.userEmail});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  late AnimationController _blobController;

  // Ticker Logic
  int _tickerIndex = 0;
  Timer? _tickerTimer;
  List<DocumentSnapshot> _tickerEvents = [];

  // Filter Variables
  String _mainFilter = 'all';
  String _timeFilter = 'all_time';
  final DateTime _now = DateTime.now();

  // Admin Info
  String? _adminDepartment;
  String? _adminName;
  bool _isSuperAdmin = false;

  // Tabs Logic
  int _currentTab = 0; // 0: Events, 1: Students

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _fetchAdminDetails();
  }

  // --- 1. FETCH ADMIN DETAILS ---
  Future<void> _fetchAdminDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          if (mounted) {
            setState(() {
              Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
              _adminDepartment = data['department'];
              _adminName = data['fullName'] ?? 'Admin'; // For Stamp
              String deptCheck = (_adminDepartment ?? '').trim();
              _isSuperAdmin = deptCheck == 'Computer Science' || deptCheck == 'CS';
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching admin details: $e");
      }
    }
  }

  @override
  void dispose() {
    _blobController.dispose();
    _tickerTimer?.cancel();
    super.dispose();
  }

  // --- TICKER LOGIC ---
  void _updateTicker(List<DocumentSnapshot> events) {
    final openEvents = events.where((doc) {
      DateTime date = (doc['date'] as Timestamp).toDate();
      return date.isAfter(DateTime.now());
    }).toList();

    if (openEvents.length != _tickerEvents.length) {
      _tickerEvents = openEvents;
      _tickerTimer?.cancel();
      if (_tickerEvents.length > 1) {
        _tickerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
          if (mounted) setState(() => _tickerIndex = (_tickerIndex + 1) % _tickerEvents.length);
        });
      } else {
        setState(() => _tickerIndex = 0);
      }
    }
  }

  // --- SORTING LOGIC ---
  List<DocumentSnapshot> _applyFilters(List<DocumentSnapshot> docs) {
    List<DocumentSnapshot> openEvents = [];
    List<DocumentSnapshot> pastEvents = [];
    for (var doc in docs) {
      DateTime date = (doc['date'] as Timestamp).toDate();
      if (date.isAfter(_now)) { openEvents.add(doc); } else { pastEvents.add(doc); }
    }
    if (_timeFilter == 'week') {
      final nextWeek = _now.add(const Duration(days: 7));
      openEvents = openEvents.where((doc) {
        DateTime date = (doc['date'] as Timestamp).toDate();
        return date.isBefore(nextWeek);
      }).toList();
    }
    openEvents.sort((a, b) => (a['date'] as Timestamp).toDate().compareTo((b['date'] as Timestamp).toDate()));
    pastEvents.sort((a, b) => (b['date'] as Timestamp).toDate().compareTo((a['date'] as Timestamp).toDate()));
    if (_mainFilter == 'upcoming') return openEvents;
    if (_mainFilter == 'past') return pastEvents;
    return [...openEvents, ...pastEvents];
  }

  // --- [NEW] TOGGLE MANAGER STATUS ---
  Future<void> _toggleManagerStatus(String uid, bool currentStatus, String name) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isManager': !currentStatus,
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(currentStatus ? "$name removed from Manager." : "$name promoted to Manager!"), backgroundColor: currentStatus ? Colors.orange : Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _startScanning(String eventId) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => ScanTicketScreen(eventId: eventId)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,

      // Create Event Button (Only visible on Events Tab)
      floatingActionButton: _currentTab == 0 ? Container(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15)]),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEventScreen())),
          backgroundColor: Colors.transparent, elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white), label: const Text("Create Event", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ) : null,

      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(theme),

                // --- TAB SWITCHER ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor)),
                    child: Row(
                      children: [
                        _buildTabButton("Events Dashboard", 0, theme),
                        _buildTabButton("Student Management", 1, theme),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // --- TAB CONTENT ---
                Expanded(
                  child: _currentTab == 0 ? _buildEventsTab(theme) : _buildStudentsTab(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, ThemeData theme) {
    bool isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? theme.primaryColor.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(color: isSelected ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  // --- TAB 1: EVENTS DASHBOARD ---
  Widget _buildEventsTab(ThemeData theme) {
    return Column(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('events').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            var allDocs = snapshot.data!.docs;
            WidgetsBinding.instance.addPostFrameCallback((_) => _updateTicker(allDocs));

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: Row(
                children: [
                  _buildStatCard("Total Events", "${allDocs.length}", Icons.event_note, Colors.blue, theme),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTickerCard(theme)),
                ],
              ),
            );
          },
        ),
        
        // Control Room Button (Only Super Admin)
        if (_isSuperAdmin)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DepartmentControlScreen())),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.red))),
                icon: const Icon(Icons.lock_person, size: 18),
                label: const Text("Department Control Room"),
              ),
            ),
          ),

        _buildFilters(theme),
        const SizedBox(height: 10),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('events').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text("No events created yet", style: theme.textTheme.bodyMedium));
              final filteredEvents = _applyFilters(snapshot.data!.docs);
              if (filteredEvents.isEmpty) return Center(child: Text("No events match filter", style: theme.textTheme.bodyMedium));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                itemCount: filteredEvents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildAdminEventCard(filteredEvents[index], theme),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- TAB 2: STUDENT MANAGEMENT (NEW LOGIC) ---
  Widget _buildStudentsTab(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users')
          .where('role', isEqualTo: 'student')
          .where('department', isEqualTo: _adminDepartment)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));
        var docs = snapshot.data!.docs;

        if (docs.isEmpty) return Center(child: Text("No active students found.", style: theme.textTheme.bodyMedium));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            return _buildStudentCard(data, docs[index].id, theme);
          },
        );
      },
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> data, String uid, ThemeData theme) {
    String name = data['fullName'] ?? 'Unknown';
    String program = data['program'] ?? 'BS';
    String sem = data['semester'] ?? '1';
    String sec = data['section'] ?? 'A';
    String id = data['sapId'] ?? data['studentId'] ?? 'N/A';
    
    // Logic Variables
    bool isManager = data['isManager'] ?? false;
    String approvedBy = data['approvedBy'] ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isManager ? Colors.orange : theme.dividerColor, width: isManager ? 2 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isManager ? Colors.orange.withOpacity(0.2) : theme.primaryColor.withOpacity(0.1),
          child: Icon(isManager ? Icons.star : Icons.person, color: isManager ? Colors.orange : theme.primaryColor),
        ),
        title: Row(
          children: [
            Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (isManager) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: const Text("MANAGER", style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold))),
            ]
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$program - $sem$sec | ID: $id", style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            // STAMP
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.verified, size: 10, color: Colors.green), const SizedBox(width: 4), Text("Approved by: $approvedBy", style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold))]),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
          onSelected: (val) {
            if (val == 'toggle') _toggleManagerStatus(uid, isManager, name);
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'toggle', child: Row(children: [Icon(isManager ? Icons.remove_circle_outline : Icons.star_border, color: isManager ? Colors.red : Colors.orange, size: 18), const SizedBox(width: 8), Text(isManager ? "Remove Manager" : "Make Manager")])),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 20)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("UOL EMS", style: theme.textTheme.headlineMedium?.copyWith(fontSize: 16)), Text(_adminDepartment ?? "Admin", style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10, color: theme.primaryColor))]),
          ]),
          Row(children: [
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VerificationListScreen())), child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending').snapshots(), builder: (context, snapshot) { bool hasPending = snapshot.hasData && snapshot.data!.docs.isNotEmpty; return Stack(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 2)), child: Icon(Icons.notifications_outlined, color: theme.iconTheme.color, size: 22)), if (hasPending) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const SizedBox(width: 4, height: 4)))]); })),
            const SizedBox(width: 15),
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())), child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 2)), child: const CircleAvatar(radius: 16, backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white, size: 18)))),
          ]),
        ],
      ),
    );
  }
  
  Widget _buildFilters(ThemeData theme) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 20), height: 50, padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor)), child: Row(children: [_buildCompactFilterTab("All", 'all', theme), _buildCompactFilterTab("Upcoming", 'upcoming', theme), _buildCompactFilterTab("Past", 'past', theme), const VerticalDivider(width: 20, indent: 8, endIndent: 8), Expanded(child: DropdownButtonHideUnderline(child: ButtonTheme(alignedDropdown: true, child: DropdownButton<String>(value: _timeFilter, dropdownColor: theme.cardColor, isExpanded: true, icon: Icon(Icons.sort, size: 18, color: theme.primaryColor), style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.bold), items: const [DropdownMenuItem(value: 'all_time', child: Text("All Time", overflow: TextOverflow.ellipsis)), DropdownMenuItem(value: 'week', child: Text("This Week", overflow: TextOverflow.ellipsis))], onChanged: (val) => setState(() => _timeFilter = val!))))) ]));
  }
  
  Widget _buildCompactFilterTab(String label, String value, ThemeData theme) { bool isSelected = _mainFilter == value; return Expanded(child: GestureDetector(onTap: () => setState(() => _mainFilter = value), child: AnimatedContainer(duration: const Duration(milliseconds: 200), alignment: Alignment.center, margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: isSelected ? theme.primaryColor.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Text(label, style: TextStyle(color: isSelected ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 11))))); }

  Widget _buildAdminEventCard(DocumentSnapshot doc, ThemeData theme) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      DateTime date = (data['date'] as Timestamp).toDate();
      bool isPast = date.isBefore(DateTime.now());
      List registered = data['registeredStudents'] ?? [];
      return Container(decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.8), borderRadius: BorderRadius.circular(20), border: Border.all(color: isPast ? Colors.red.withOpacity(0.2) : theme.dividerColor)), child: ClipRRect(borderRadius: BorderRadius.circular(20), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(data['title'] ?? 'No Title', style: theme.textTheme.headlineSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: isPast ? Colors.grey : null))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.people, size: 12, color: Colors.grey), const SizedBox(width: 4), Text("${registered.length}", style: TextStyle(fontSize: 10, color: theme.primaryColor, fontWeight: FontWeight.bold))]))]), const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton(onPressed: () {Navigator.push(context, MaterialPageRoute(builder: (context) => ManageEventScreen(eventData: {'id': doc.id, ...data, 'date': date})));}, child: const Text("Manage"))), const SizedBox(width: 10), Expanded(child: ElevatedButton.icon(onPressed: () => _startScanning(doc.id), icon: const Icon(Icons.qr_code_scanner, size: 16), label: const Text("Scan")))])])))));
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ThemeData theme) {return Expanded(child: Container(height: 75, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)), Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11))]), Icon(icon, color: color, size: 24)])));}
  Widget _buildTickerCard(ThemeData theme) {if (_tickerEvents.isEmpty) return Container(height: 75, decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))), child: const Center(child: Text("No Upcoming Events"))); var event = _tickerEvents[_tickerIndex].data() as Map<String, dynamic>; return Container(height: 75, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withOpacity(0.2))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: Column(key: ValueKey(_tickerIndex), crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text("${(event['registeredStudents'] as List).length}", style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)), Text("Reg: ${event['title']}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)]))), const Icon(Icons.show_chart, color: Colors.green, size: 24)]));}
  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));}
}
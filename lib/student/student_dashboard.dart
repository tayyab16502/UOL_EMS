import 'dart:async';
import 'dart:math';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Date Formatting
import '../theme/theme.dart';
import '../common/profile.dart';
import 'register_event.dart';
import 'event_detail.dart'; // Ticket Screen
import '../guard/guard_dashboard.dart';
import '../common/login.dart'; // For Logout navigation
import 'package:uol_ems/admin/verification_list_screen.dart'; // Import Verification Screen

class StudentDashboard extends StatefulWidget {
  final String userEmail;
  const StudentDashboard({super.key, required this.userEmail});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with SingleTickerProviderStateMixin {
  // Default filter set to 'registered'
  String _mainFilter = 'registered';
  String _timeFilter = 'all_time';

  // User Info
  String? _currentUserUid;

  late AnimationController _blobController;
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserUid = user.uid;
    }

    // Timer to update countdowns
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _blobController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // --- UPDATED FILTERING LOGIC (With Department Check) ---
  List<DocumentSnapshot> _filterEvents(List<DocumentSnapshot> docs, String userDepartment) {
    if (_currentUserUid == null) return [];

    List<DocumentSnapshot> tempEvents = docs;

    // 1. Time Filter
    if (_timeFilter == 'week') {
      final nextWeek = _now.add(const Duration(days: 7));
      tempEvents = tempEvents.where((doc) {
        DateTime date = (doc['date'] as Timestamp).toDate();
        return date.isAfter(_now) && date.isBefore(nextWeek);
      }).toList();
    } else if (_timeFilter == 'month') {
      tempEvents = tempEvents.where((doc) {
        DateTime date = (doc['date'] as Timestamp).toDate();
        return date.month == _now.month && date.year == _now.year;
      }).toList();
    } else if (_timeFilter == '3_months') {
      final threeMonths = _now.add(const Duration(days: 90));
      tempEvents = tempEvents.where((doc) {
        DateTime date = (doc['date'] as Timestamp).toDate();
        return date.isBefore(threeMonths);
      }).toList();
    }

    // 2. Main Filter (Registered vs Upcoming)
    if (_mainFilter == 'registered') {
      // Logic: Show ALL events I registered for, regardless of department
      tempEvents = tempEvents.where((doc) {
        List registered = doc['registeredStudents'] ?? [];
        return registered.contains(_currentUserUid);
      }).toList();
    }
    else if (_mainFilter == 'upcoming') {
      tempEvents = tempEvents.where((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        DateTime date = (data['date'] as Timestamp).toDate();
        List registered = data['registeredStudents'] ?? [];

        // --- NEW: DEPARTMENT CHECK ---
        String eventDept = data['department'] ?? 'General';

        // Show if: (General Event) OR (My Department Event)
        // Note: 'CS (Computer Science)' might be saved in profile, so we check contains or exact match
        bool isRelevant = eventDept == 'General' ||
            eventDept == 'Computer Science' || // CS sees CS events
            eventDept == userDepartment ||     // Exact Match
            userDepartment.contains(eventDept) || // Partial Match
            eventDept == 'CS'; // Legacy support

        // Logic: Future Event + Not Registered + Relevant Department
        return date.isAfter(_now) && !registered.contains(_currentUserUid) && isRelevant;
      }).toList();
    }

    // 3. Sort by Date
    tempEvents.sort((a, b) {
      DateTime dateA = (a['date'] as Timestamp).toDate();
      DateTime dateB = (b['date'] as Timestamp).toDate();
      return dateA.compareTo(dateB);
    });

    return tempEvents;
  }

  // --- NAVIGATION ACTIONS ---

  void _goToGuardPanel() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => GuardDashboard(guardEmail: widget.userEmail)));
  }

  void _registerEvent(String eventId, String title, double fee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisterEventScreen(
          eventData: {'id': eventId, 'title': title, 'fee': fee.toString()},
        ),
      ),
    );
  }

  void _openTicket(DocumentSnapshot doc) {
    Map<String, dynamic> eventData = doc.data() as Map<String, dynamic>;
    eventData['id'] = doc.id;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(eventData: eventData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          // --- REAL-TIME USER DATA STREAM (For Role, Dept & Status) ---
          StreamBuilder<DocumentSnapshot>(
              stream: _currentUserUid != null
                  ? FirebaseFirestore.instance.collection('users').doc(_currentUserUid).snapshots()
                  : null,
              builder: (context, userSnapshot) {

                if (!userSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var userData = userSnapshot.data!.data() as Map<String, dynamic>?;

                // --- 1. BLOCK CHECK ---
                // Agar status 'blocked' hai to Access Denied
                if (userData == null || userData['status'] == 'blocked') {
                  return _buildBlockedScreen(theme);
                }

                // Get User Details
                String role = userData['role'] ?? 'student';
                bool isGuard = role == 'guard';
                String userDepartment = userData['department'] ?? 'General';

                // --- MANAGER & CLASS DETAILS ---
                bool isManager = userData['isManager'] == true;
                String myProgram = userData['program'] ?? '';
                String mySection = userData['section'] ?? '';
                String mySemester = userData['semester'] ?? '';

                return SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      // Updated Header with Smart Notification Logic
                      _buildHeader(theme, isManager, userDepartment, myProgram, mySemester, mySection),

                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('events').snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: theme.primaryColor));

                            var allDocs = snapshot.data!.docs;

                            // UPDATED: Passing Department to Filter
                            var filteredDocs = _filterEvents(allDocs, userDepartment);

                            // Calculate Stats
                            int registeredCount = 0;
                            int upcomingCount = 0;
                            bool hasNewUpcoming = false;

                            if (_currentUserUid != null) {
                              // Registered Count
                              registeredCount = allDocs.where((d) => (d['registeredStudents'] as List).contains(_currentUserUid)).length;

                              // Upcoming Count (Relevant Only)
                              var upcomingEvents = allDocs.where((d) {
                                Map<String, dynamic> data = d.data() as Map<String, dynamic>;
                                DateTime date = (data['date'] as Timestamp).toDate();
                                List registered = data['registeredStudents'] ?? [];
                                String eventDept = data['department'] ?? 'General';

                                bool isRelevant = eventDept == 'General' ||
                                    eventDept == 'Computer Science' ||
                                    eventDept == userDepartment ||
                                    userDepartment.contains(eventDept) ||
                                    eventDept == 'CS';

                                return date.isAfter(_now) && !registered.contains(_currentUserUid) && isRelevant;
                              }).toList();

                              upcomingCount = upcomingEvents.length;
                              hasNewUpcoming = upcomingCount > 0;
                            }

                            return SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Stats Row
                                  Row(
                                    children: [
                                      _buildStatCard("Registered", "$registeredCount", Icons.check_circle_outline, Colors.green, theme),
                                      const SizedBox(width: 12),
                                      _buildStatCard("Upcoming", "$upcomingCount", Icons.calendar_today_outlined, Colors.blue, theme),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  // Filter Row
                                  Container(
                                    height: 50,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: theme.cardColor.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: theme.dividerColor),
                                    ),
                                    child: Row(
                                      children: [
                                        _buildCompactFilterTab("Registered", 'registered', theme, false),
                                        _buildCompactFilterTab("Upcoming", 'upcoming', theme, hasNewUpcoming),
                                        const VerticalDivider(width: 20, indent: 8, endIndent: 8),
                                        Expanded(
                                          child: DropdownButtonHideUnderline(
                                            child: ButtonTheme(
                                              alignedDropdown: true,
                                              child: DropdownButton<String>(
                                                value: _timeFilter,
                                                dropdownColor: theme.cardColor,
                                                isExpanded: true,
                                                icon: Icon(Icons.sort, size: 18, color: theme.primaryColor),
                                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                                                items: const [
                                                  DropdownMenuItem(value: 'all_time', child: Text("All Time", overflow: TextOverflow.ellipsis)),
                                                  DropdownMenuItem(value: 'week', child: Text("This Week", overflow: TextOverflow.ellipsis)),
                                                  DropdownMenuItem(value: 'month', child: Text("This Month", overflow: TextOverflow.ellipsis)),
                                                  DropdownMenuItem(value: '3_months', child: Text("Next 3 Months", overflow: TextOverflow.ellipsis)),
                                                ],
                                                onChanged: (val) => setState(() => _timeFilter = val!),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // List
                                  filteredDocs.isEmpty
                                      ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 50),
                                      child: Text(
                                        _mainFilter == 'registered' ? "You haven't registered yet" : "No new events for $userDepartment",
                                        style: theme.textTheme.bodyMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                      : ListView.separated(
                                    physics: const NeverScrollableScrollPhysics(),
                                    shrinkWrap: true,
                                    itemCount: filteredDocs.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                                    itemBuilder: (context, index) {
                                      // Pass isGuard to update buttons
                                      return _buildEventCard(filteredDocs[index], theme, isGuard);
                                    },
                                  ),
                                  const SizedBox(height: 80),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  // --- BLOCKED SCREEN WIDGET ---
  Widget _buildBlockedScreen(ThemeData theme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 60, color: Colors.red),
            const SizedBox(height: 20),
            Text("Access Revoked", style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.red)),
            const SizedBox(height: 16),
            Text(
              "Your account has been blocked by the Administrator.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: 16),
            ),
            const SizedBox(height: 30),
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
                label: const Text("Logout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UPDATED HEADER: Accepts Manager Details for Smart Notification
  Widget _buildHeader(ThemeData theme, bool isManager, String dept, String prog, String sem, String sec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.school, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("UOL EMS", style: theme.textTheme.headlineMedium?.copyWith(fontSize: 16)), Text("Student Portal", style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10))]),
            ],
          ),

          Row(
            children: [
              // --- SMART MANAGER NOTIFICATION ---
              // Only Show if User is a Manager
              if (isManager) ...[
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VerificationListScreen())),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('status', isEqualTo: 'pending')
                        .where('department', isEqualTo: dept)
                        .where('program', isEqualTo: prog)
                        .where('semester', isEqualTo: sem)
                        .where('section', isEqualTo: sec)
                        .snapshots(),
                    builder: (context, snapshot) {
                      // Check if any pending students exist for THIS Specific Class
                      bool hasPending = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

                      return Stack(
                        children: [
                          Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 2)),
                              child: Icon(Icons.notifications_outlined, color: theme.iconTheme.color, size: 22)
                          ),
                          // Show RED DOT only if hasPending is true
                          if (hasPending)
                            Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    child: const SizedBox(width: 4, height: 4)
                                )
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 15),
              ],

              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
                child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 2)), child: const CircleAvatar(radius: 16, backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white, size: 18))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ThemeData theme) {
    return Expanded(
      child: Container(
        height: 75,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)), Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11))]),
            Icon(icon, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactFilterTab(String label, String value, ThemeData theme, bool showDot) {
    bool isSelected = _mainFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mainFilter = value),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: isSelected ? theme.primaryColor.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
              child: Text(label, style: TextStyle(color: isSelected ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            if (showDot && !isSelected)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(DocumentSnapshot doc, ThemeData theme, bool isGuard) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    String eventId = doc.id;

    String title = data['title'] ?? 'No Title';
    String description = data['description'] ?? '';
    String location = data['location'] ?? 'Unknown';
    String timeStr = data['time'] ?? '';
    double fee = (data['fee'] is int) ? (data['fee'] as int).toDouble() : (data['fee'] ?? 0.0);

    DateTime date = (data['date'] as Timestamp).toDate();
    List registered = data['registeredStudents'] ?? [];
    bool isRegistered = registered.contains(_currentUserUid);

    Duration difference = date.difference(_now);
    bool showCountdown = difference.inHours < 24 && !difference.isNegative;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isRegistered ? Colors.green.withOpacity(0.3) : theme.dividerColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.bold))),
                if (isGuard)
                  Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.security, size: 14, color: Colors.orange)),
                if (isRegistered)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.check_circle, size: 12, color: Colors.green), SizedBox(width: 4), Text("Registered", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))])),
              ],
            ),
            const SizedBox(height: 6),
            Text(description, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),

            if (showCountdown)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.timer_outlined, color: Colors.orange, size: 14), const SizedBox(width: 6), Text("Starts in: ${difference.inHours}h ${difference.inMinutes % 60}m", style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 11))]),
              ),

            Row(children: [
              const Icon(Icons.calendar_month_outlined, size: 14, color: Colors.teal), const SizedBox(width: 6), Text(DateFormat('dd MMM yyyy').format(date), style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 16),
              const Icon(Icons.access_time_rounded, size: 14, color: Colors.teal), const SizedBox(width: 6), Text(timeStr, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 6),
            Row(children: [const Icon(Icons.location_on_outlined, size: 14, color: Colors.teal), const SizedBox(width: 6), Text(location, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500))]),
            const SizedBox(height: 16),

            // --- DYNAMIC BUTTONS ---
            if (isRegistered) ...[
              if (isGuard)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                          onPressed: () => _openTicket(doc),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                          child: const Text("My Ticket", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: ElevatedButton.icon(
                            onPressed: _goToGuardPanel,
                            icon: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.white),
                            label: const Text("Scan", style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800)
                        )
                    ),
                  ],
                )
              else
                SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                        onPressed: () => _openTicket(doc),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1), elevation: 0, side: const BorderSide(color: Colors.green)),
                        child: const Text("View Ticket", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                    )
                )
            ]
            else
              SizedBox(width: double.infinity, height: 45, child: ElevatedButton(onPressed: () => _registerEvent(eventId, title, fee), style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor), child: const Text("Register Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
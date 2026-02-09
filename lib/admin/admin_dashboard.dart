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

// --- IMPORT NEW MODULAR SCREENS ---
import 'verification_list_screen.dart';
import 'all_students_screen.dart';
import 'department_control_screen.dart';

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
  bool _isSuperAdmin = false;
  bool _isLoadingAdminInfo = true; // To track loading state

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

              // Normalize String
              String deptCheck = (_adminDepartment ?? '').trim();
              _isSuperAdmin = deptCheck == 'Computer Science' || deptCheck == 'CS';
              _isLoadingAdminInfo = false;
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching admin details: $e");
        if(mounted) setState(() => _isLoadingAdminInfo = false);
      }
    }
  }

  @override
  void dispose() {
    _blobController.dispose();
    _tickerTimer?.cancel();
    super.dispose();
  }

  // --- HELPER: GET NOTIFICATION STREAM ---
  // Ye stream ab sirf usi department k pending students lay gi jo Admin ka department ha
  Stream<QuerySnapshot> _getPendingStream() {
    // Agar admin info load nahi hoi, to empty stream return karo (no dot)
    if (_isLoadingAdminInfo || _adminDepartment == null) {
      return const Stream.empty();
    }

    Query query = FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending');

    // Filter Logic:
    // Sirf apnay department k students show karo
    // Note: Agar aap chahtay hain k Super Admin (CS) sab ko dekh sakay, to if condition hata dein.
    // Filhal strict filtering laga rahay hain taakay Math walay ko Physics ka dot na dikhay.
    query = query.where('department', isEqualTo: _adminDepartment);

    return query.snapshots();
  }

  // --- 2. TICKER LOGIC ---
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

  // --- 3. SORTING LOGIC ---
  List<DocumentSnapshot> _applyFilters(List<DocumentSnapshot> docs) {
    List<DocumentSnapshot> openEvents = [];
    List<DocumentSnapshot> pastEvents = [];

    for (var doc in docs) {
      DateTime date = (doc['date'] as Timestamp).toDate();
      if (date.isAfter(_now)) {
        openEvents.add(doc);
      } else {
        pastEvents.add(doc);
      }
    }

    if (_timeFilter == 'week') {
      final nextWeek = _now.add(const Duration(days: 7));
      openEvents = openEvents.where((doc) {
        DateTime date = (doc['date'] as Timestamp).toDate();
        return date.isBefore(nextWeek);
      }).toList();
    }

    openEvents.sort((a, b) {
      DateTime dateA = (a['date'] as Timestamp).toDate();
      DateTime dateB = (b['date'] as Timestamp).toDate();
      return dateA.compareTo(dateB);
    });

    pastEvents.sort((a, b) {
      DateTime dateA = (a['date'] as Timestamp).toDate();
      DateTime dateB = (b['date'] as Timestamp).toDate();
      return dateB.compareTo(dateA);
    });

    if (_mainFilter == 'upcoming') return openEvents;
    if (_mainFilter == 'past') return pastEvents;

    return [...openEvents, ...pastEvents];
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

      // Create Event Button
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15)],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEventScreen())),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("Create Event", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),

      body: Stack(
        children: [
          // Background
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(theme),

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('events').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(height: 100);
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

                const SizedBox(height: 16),

                // --- ACTION BUTTONS (Directory & Control Room) ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // 1. Directory Button (Now with Department Filtered Red Dot)
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                            stream: _getPendingStream(), // Updated Stream with Filter
                            builder: (context, snapshot) {
                              bool hasPending = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

                              return ElevatedButton.icon(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AllStudentsScreen())),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.cardColor.withOpacity(0.8),
                                  foregroundColor: theme.primaryColor,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.dividerColor)),
                                  elevation: 0,
                                ),
                                // Updated Icon with Red Dot
                                icon: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(Icons.people_alt_outlined, size: 20),
                                    if (hasPending)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: theme.cardColor, width: 1.5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                label: const Text("Directory"),
                              );
                            }
                        ),
                      ),

                      // 2. Control Room Button (ONLY FOR BOSS / CS)
                      if (_isSuperAdmin) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DepartmentControlScreen())),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.withOpacity(0.1),
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.red)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.lock_person_outlined, size: 20),
                            label: const Text("Control Room"),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                _buildFilters(theme),
                const SizedBox(height: 16),

                // --- EVENTS LIST ---
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
                        itemBuilder: (context, index) {
                          return _buildAdminEventCard(filteredEvents[index], theme);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("UOL EMS", style: theme.textTheme.headlineMedium?.copyWith(fontSize: 16)),
                Text(_adminDepartment ?? "Admin", style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10, color: theme.primaryColor)),
              ]),
            ],
          ),

          Row(
            children: [
              // Notification Bell (Now with Department Filtered Red Dot)
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const VerificationListScreen())),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _getPendingStream(), // Updated Stream with Filter
                  builder: (context, snapshot) {
                    bool hasPending = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                    return Stack(
                      children: [
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.primaryColor, width: 2)), child: Icon(Icons.notifications_outlined, color: theme.iconTheme.color, size: 22)),
                        if (hasPending)
                          Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 1.5)
                                  ),
                                  child: const SizedBox(width: 6, height: 6)
                              )
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 15),
              // Profile Icon
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

  Widget _buildFilters(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.dividerColor)),
      child: Row(
        children: [
          _buildCompactFilterTab("All", 'all', theme),
          _buildCompactFilterTab("Upcoming", 'upcoming', theme),
          _buildCompactFilterTab("Past", 'past', theme),
          const VerticalDivider(width: 20, indent: 8, endIndent: 8),
          Expanded(child: DropdownButtonHideUnderline(child: ButtonTheme(alignedDropdown: true, child: DropdownButton<String>(value: _timeFilter, dropdownColor: theme.cardColor, isExpanded: true, icon: Icon(Icons.sort, size: 18, color: theme.primaryColor), style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.bold), items: const [DropdownMenuItem(value: 'all_time', child: Text("All Time", overflow: TextOverflow.ellipsis)), DropdownMenuItem(value: 'week', child: Text("This Week", overflow: TextOverflow.ellipsis))], onChanged: (val) => setState(() => _timeFilter = val!))))),
        ],
      ),
    );
  }

  Widget _buildCompactFilterTab(String label, String value, ThemeData theme) {
    bool isSelected = _mainFilter == value;
    return Expanded(child: GestureDetector(onTap: () => setState(() => _mainFilter = value), child: AnimatedContainer(duration: const Duration(milliseconds: 200), alignment: Alignment.center, margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: isSelected ? theme.primaryColor.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Text(label, style: TextStyle(color: isSelected ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)))));
  }

  Widget _buildAdminEventCard(DocumentSnapshot doc, ThemeData theme) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    DateTime date = (data['date'] as Timestamp).toDate();
    bool isPast = date.isBefore(DateTime.now());
    List registered = data['registeredStudents'] ?? [];

    return Container(
      decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.8), borderRadius: BorderRadius.circular(20), border: Border.all(color: isPast ? Colors.red.withOpacity(0.2) : theme.dividerColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(
                          data['title'] ?? 'No Title',
                          style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isPast ? Colors.grey : null
                          )
                      )
                  ),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.people, size: 12, color: Colors.grey), const SizedBox(width: 4), Text("${registered.length}", style: TextStyle(fontSize: 10, color: theme.primaryColor, fontWeight: FontWeight.bold))]))
                ]),
                const SizedBox(height: 6),
                Text(data['description'] ?? '', style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                Row(children: [Icon(Icons.calendar_today, size: 12, color: theme.primaryColor), const SizedBox(width: 4), Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(width: 12), Icon(Icons.access_time, size: 12, color: theme.primaryColor), const SizedBox(width: 4), Text(data['time'] ?? '--:--', style: const TextStyle(fontSize: 11, color: Colors.grey))]),
                const SizedBox(height: 16),

                // --- MANAGE & SCAN BUTTONS ---
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () {Navigator.push(context, MaterialPageRoute(builder: (context) => ManageEventScreen(eventData: {'id': doc.id, ...data, 'date': date})));}, style: OutlinedButton.styleFrom(side: BorderSide(color: theme.primaryColor.withOpacity(0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text("Manage", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton.icon(onPressed: () => _startScanning(doc.id), icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 16), label: const Text("Scan", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))))
                ])
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ThemeData theme) {
    return Expanded(child: Container(height: 75, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)), Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11))]), Icon(icon, color: color, size: 24)])));
  }

  Widget _buildTickerCard(ThemeData theme) {
    if (_tickerEvents.isEmpty) return Container(height: 75, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.2))), child: const Center(child: Text("No Upcoming Events")));
    var event = _tickerEvents[_tickerIndex].data() as Map<String, dynamic>;
    List reg = event['registeredStudents'] ?? [];
    return Container(height: 75, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: theme.cardColor.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.withOpacity(0.2))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 600), child: Column(key: ValueKey(_tickerIndex), crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text("${reg.length}", style: theme.textTheme.headlineLarge?.copyWith(fontSize: 24)), Text("Reg: ${event['title']}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)]))), const Icon(Icons.show_chart, color: Colors.green, size: 24)]));
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
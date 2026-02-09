import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/theme.dart';

class ManageEventScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;

  const ManageEventScreen({super.key, required this.eventData});

  @override
  State<ManageEventScreen> createState() => _ManageEventScreenState();
}

class _ManageEventScreenState extends State<ManageEventScreen> with TickerProviderStateMixin {
  late AnimationController _blobController;
  late TabController _tabController;

  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _locController;
  late TextEditingController _feeController;
  late TextEditingController _capacityController;
  final TextEditingController _searchController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _searchQuery = "";

  bool _isExporting = false;
  bool _isSaving = false;

  // --- PERMISSION FLAGS ---
  bool _hasEditPermission = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);

    // 3 Tabs: Details, Attendees, Guard Logs
    _tabController = TabController(length: 3, vsync: this);

    _titleController = TextEditingController(text: widget.eventData['title']);
    _descController = TextEditingController(text: widget.eventData['description']);
    _locController = TextEditingController(text: widget.eventData['location']);
    _feeController = TextEditingController(text: widget.eventData['fee']?.toString() ?? "0");
    _capacityController = TextEditingController(text: widget.eventData['capacity']?.toString() ?? "50");

    if (widget.eventData['date'] is Timestamp) {
      _selectedDate = (widget.eventData['date'] as Timestamp).toDate();
    } else {
      _selectedDate = DateTime.now();
    }

    try {
      _selectedTime = TimeOfDay.now();
    } catch (e) {
      _selectedTime = TimeOfDay.now();
    }

    // --- CHECK PERMISSIONS ON INIT ---
    _checkPermissions();
  }

  // --- UPDATED: LOGIC TO CHECK IF ADMIN CAN EDIT (FLAT STRUCTURE) ---
  Future<void> _checkPermissions() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. If I am the Organizer -> Allow (Simple check)
      if (user.uid == widget.eventData['organizerUid']) {
        if (mounted) setState(() { _hasEditPermission = true; _checkingPermissions = false; });
        return;
      }

      // 2. If I am the BOSS (CS Admin) -> Allow
      try {
        // [FLAT STRUCTURE UPDATE]
        // Check 'users' collection directly to see department
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          String myDept = userDoc.get('department') ?? '';

          // Normalize (Trim spaces)
          myDept = myDept.trim();

          // Final Boss Check
          if (myDept == 'Computer Science' || myDept == 'CS') {
            if (mounted) setState(() { _hasEditPermission = true; _checkingPermissions = false; });
            return;
          }
        }
      } catch (e) {
        debugPrint("Permission Check Error: $e");
      }
    }

    // If neither Organizer nor Boss -> Read Only mode
    if (mounted) setState(() { _hasEditPermission = false; _checkingPermissions = false; });
  }

  @override
  void dispose() {
    _blobController.dispose();
    _tabController.dispose();
    _titleController.dispose(); _descController.dispose();
    _locController.dispose(); _feeController.dispose();
    _capacityController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---

  Future<void> _exportToExcel(List<Map<String, dynamic>> data) async {
    setState(() => _isExporting = true);
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];

      // Headers
      List<String> headers = ["Name", "ID", "Status", "Time", "Details"];
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (var rowData in data) {
        List<CellValue> row = [
          TextCellValue(rowData['name'] ?? '-'),
          TextCellValue(rowData['id'] ?? '-'),
          TextCellValue(rowData['status'] ?? '-'),
          TextCellValue(rowData['time'] ?? '-'),
          TextCellValue(rowData['details'] ?? '-'),
        ];
        sheetObject.appendRow(row);
      }

      var fileBytes = excel.save();
      var directory = await getTemporaryDirectory();
      String fileName = "${_titleController.text.replaceAll(' ', '_')}_Report.xlsx";
      File file = File('${directory.path}/$fileName');

      if (fileBytes != null) {
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Event Report');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Failed: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_hasEditPermission) return; // Security Check

    setState(() => _isSaving = true);
    try {
      DateTime fullDate = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        _selectedTime!.hour, _selectedTime!.minute,
      );

      await FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']).update({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'location': _locController.text.trim(),
        'fee': int.tryParse(_feeController.text) ?? 0,
        'capacity': int.tryParse(_capacityController.text) ?? 50,
        'date': Timestamp.fromDate(fullDate),
        'time': _selectedTime!.format(context),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Updated Successfully!"), backgroundColor: Colors.green));
      Navigator.pop(context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update Failed: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteEvent() async {
    if (!_hasEditPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Access Denied: View Only Mode"), backgroundColor: Colors.red));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text("Delete Event?", style: TextStyle(color: Colors.red)),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Deleted"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _endEvent() async {
    if (!_hasEditPermission) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text("End Event?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("This will mark the event as completed. No further check-ins will be allowed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('events').doc(widget.eventData['id']).update({
                  'status': 'ended'
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Ended Successfully"), backgroundColor: Colors.orange));
                  Navigator.pop(context);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
              }
            },
            child: const Text("End Event", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGuardRole(String uid, bool isGuard) async {
    if (!_hasEditPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Only Event Organizer/Boss can manage guards."), backgroundColor: Colors.red));
      return;
    }

    try {
      // [FLAT STRUCTURE] Role update directly on 'users' collection
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': isGuard ? 'student' : 'guard'
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isGuard ? "Removed from Guard" : "Promoted to Guard"),
        backgroundColor: isGuard ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 1),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update role"), backgroundColor: Colors.red));
    }
  }

  // --- HELPER: GROUPING LOGIC ---
  String _getGroupLabel(Map<String, dynamic> data) {
    String p = data['program'] ?? '';
    String f = data['field'] ?? '';
    String s = data['semester'] ?? '';
    String sec = data['section'] ?? '';
    if (p.isEmpty && f.isEmpty) return "Unassigned Class";
    return "$p-$f-$s$sec".toUpperCase();
  }

  Map<String, List<DocumentSnapshot>> _groupStudents(List<DocumentSnapshot> docs) {
    List<DocumentSnapshot> filtered = docs.where((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String name = (data['fullName'] ?? '').toString().toLowerCase();
      String id = (data['studentId'] ?? '').toString().toLowerCase();
      String classStr = _getGroupLabel(data).toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || id.contains(_searchQuery.toLowerCase()) || classStr.contains(_searchQuery.toLowerCase());
    }).toList();

    List<DocumentSnapshot> guards = [];
    List<DocumentSnapshot> students = [];

    for (var doc in filtered) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      if (data['role'] == 'guard') {
        guards.add(doc);
      } else {
        students.add(doc);
      }
    }

    Map<String, List<DocumentSnapshot>> groups = {};
    if (guards.isNotEmpty) groups["EVENT GUARDS"] = guards;

    students.sort((a, b) {
      String nameA = (a['fullName'] ?? '').toString();
      String nameB = (b['fullName'] ?? '').toString();
      return nameA.compareTo(nameB);
    });

    for (var doc in students) {
      String label = _getGroupLabel(doc.data() as Map<String, dynamic>);
      if (!groups.containsKey(label)) groups[label] = [];
      groups[label]!.add(doc);
    }

    var sortedKeys = groups.keys.toList()..sort();
    if (sortedKeys.contains("EVENT GUARDS")) {
      sortedKeys.remove("EVENT GUARDS");
      sortedKeys.insert(0, "EVENT GUARDS");
    }

    Map<String, List<DocumentSnapshot>> sortedGroups = {};
    for (var key in sortedKeys) sortedGroups[key] = groups[key]!;

    return sortedGroups;
  }

  // --- HELPER: GUARD LOGS GROUPING ---
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupLogsByGuard(List<QueryDocumentSnapshot> logs) {
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

    for (var doc in logs) {
      var data = doc.data() as Map<String, dynamic>;
      String guardName = data['guardName'] ?? 'Unknown Guard';
      String type = (data['status'] == 'inside') ? 'Entries' : 'Exits';

      if (!grouped.containsKey(guardName)) grouped[guardName] = {'Entries': [], 'Exits': []};

      Timestamp? time = (data['status'] == 'inside') ? data['lastEntry'] : data['lastExit'];
      String timeStr = time != null ? DateFormat('hh:mm a').format(time.toDate()) : '-';

      grouped[guardName]![type]!.add({
        'studentName': data['name'] ?? 'Unknown',
        'studentId': data['regId'] ?? 'N/A',
        'time': timeStr
      });
    }
    return grouped;
  }

  // --- PICKERS (UI Disabled if No Permission) ---
  Future<void> _pickDate() async {
    if (!_hasEditPermission) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: AppTheme.uolPrimary, onPrimary: Colors.white, onSurface: Colors.black),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    if (!_hasEditPermission) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: AppTheme.uolPrimary, onPrimary: Colors.white, onSurface: Colors.black),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: theme.iconTheme.color),
        title: Text("Event Control", style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          // Delete button only if permission exists
          if (_hasEditPermission)
            IconButton(onPressed: _deleteEvent, icon: const Icon(Icons.delete_outline, color: Colors.red)),
        ],
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          SafeArea(
            child: Column(
              children: [
                // View Only Banner (If applicable)
                if (!_checkingPermissions && !_hasEditPermission)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.withOpacity(0.2),
                    child: const Text(
                      "VIEW ONLY MODE (You are not the organizer)",
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),

                Container(
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 20),
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 10)],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    tabs: const [
                      Tab(text: "Details"),
                      Tab(text: "Attendees"),
                      Tab(text: "Guard Logs"),
                    ],
                  ),
                ),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEditTab(theme),
                      _buildGroupedAttendeesTab(theme),
                      _buildGuardLogsTab(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: EDIT DETAILS ---
  Widget _buildEditTab(ThemeData theme) {
    int totalRegistered = (widget.eventData['registeredStudents'] as List?)?.length ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Card (Live Stream)
          StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('events').doc(widget.eventData['id'])
                  .collection('attendance')
                  .where('status', isEqualTo: 'inside')
                  .snapshots(),
              builder: (context, snapshot) {
                int enteredCount = 0;
                if (snapshot.hasData) {
                  enteredCount = snapshot.data!.docs.length;
                }

                double progress = totalRegistered == 0 ? 0 : enteredCount / totalRegistered;

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.cardColor.withOpacity(0.8), theme.cardColor.withOpacity(0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Live Attendance", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text("$enteredCount", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.textTheme.headlineMedium?.color)),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                                    child: Text("/ $totalRegistered", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.wifi_tethering, color: Colors.green, size: 24),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.grey.withOpacity(0.1), valueColor: const AlwaysStoppedAnimation(AppTheme.uolPrimary)),
                      ),
                      const SizedBox(height: 8),
                      Text("${(progress * 100).toInt()}% Entered", style: TextStyle(color: theme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }
          ),

          const SizedBox(height: 24),
          Text("Event Details", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Inputs (Disabled via IgnorePointer if no permission)
          IgnorePointer(
            ignoring: !_hasEditPermission,
            child: Column(
              children: [
                _buildModernInput(_titleController, "Event Title", Icons.title, theme),
                const SizedBox(height: 16),
                _buildModernInput(_descController, "Description", Icons.description_outlined, theme, maxLines: 4),
                const SizedBox(height: 16),
                _buildModernInput(_locController, "Location", Icons.location_on_outlined, theme),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildGlassPicker(Icons.calendar_month, _selectedDate == null ? "Date" : "${_selectedDate!.day}/${_selectedDate!.month}", () => _pickDate(), theme)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildGlassPicker(Icons.access_time, _selectedTime == null ? "Time" : _selectedTime!.format(context), () => _pickTime(), theme)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildModernInput(_feeController, "Fee", Icons.attach_money, theme)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildModernInput(_capacityController, "Cap", Icons.people_outline, theme)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // Save Button
          Opacity(
            opacity: _hasEditPermission ? 1.0 : 0.5,
            child: Container(
              width: double.infinity, height: 55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _hasEditPermission ? (_isSaving ? null : _saveChanges) : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Center(
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Save Changes", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // End Event Button
          Opacity(
            opacity: _hasEditPermission ? 1.0 : 0.5,
            child: Container(
              width: double.infinity, height: 55,
              decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.red.withOpacity(0.5))
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _hasEditPermission ? _endEvent : null,
                  borderRadius: BorderRadius.circular(18),
                  child: const Center(
                    child: Text("End Event", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // --- TAB 2: GROUPED ATTENDEES ---
  Widget _buildGroupedAttendeesTab(ThemeData theme) {
    List<dynamic> regIds = widget.eventData['registeredStudents'] ?? [];
    if (regIds.isEmpty) return const Center(child: Text("No students registered."));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: "Search students...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.cardColor.withOpacity(0.6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
            ),
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              var allUsers = snapshot.data!.docs;
              var eventUsers = allUsers.where((doc) => regIds.contains(doc.id)).toList();

              if (eventUsers.isEmpty) return const Center(child: Text("No data found."));

              Map<String, List<DocumentSnapshot>> grouped = _groupStudents(eventUsers);

              if (grouped.isEmpty) return const Center(child: Text("No matches found."));

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: grouped.length,
                itemBuilder: (context, index) {
                  String key = grouped.keys.elementAt(index);
                  List<DocumentSnapshot> students = grouped[key]!;
                  bool isGuardGroup = key == "EVENT GUARDS";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isGuardGroup ? theme.primaryColor.withOpacity(0.1) : theme.cardColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isGuardGroup ? theme.primaryColor : theme.dividerColor),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: isGuardGroup,
                        leading: isGuardGroup
                            ? Icon(Icons.security, color: theme.primaryColor)
                            : Icon(Icons.class_, color: Colors.grey),
                        title: Text(
                            key,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isGuardGroup
                                    ? theme.primaryColor
                                    : (theme.brightness == Brightness.dark ? Colors.white : Colors.black87)
                            )
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: isGuardGroup ? theme.primaryColor : Colors.grey.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10)
                          ),
                          child: Text("${students.length}", style: TextStyle(fontSize: 12, color: isGuardGroup ? Colors.white : (theme.brightness == Brightness.dark ? Colors.white : Colors.black), fontWeight: FontWeight.bold)),
                        ),
                        children: students.map((doc) => _buildStudentActionCard(doc, theme)).toList(),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStudentActionCard(DocumentSnapshot doc, ThemeData theme) {
    var data = doc.data() as Map<String, dynamic>;
    bool isGuard = data['role'] == 'guard';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: isGuard ? theme.primaryColor : Colors.grey.withOpacity(0.2),
        child: Icon(isGuard ? Icons.security : Icons.person, color: isGuard ? Colors.white : Colors.grey, size: 20),
      ),
      title: Text(data['fullName'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(data['studentId'] ?? 'N/A', style: const TextStyle(fontSize: 12)),
      trailing: _hasEditPermission ? SizedBox(
        width: 100,
        height: 35,
        child: ElevatedButton(
          onPressed: () => _toggleGuardRole(doc.id, isGuard),
          style: ElevatedButton.styleFrom(
            backgroundColor: isGuard ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
            elevation: 0,
            padding: EdgeInsets.zero,
            side: BorderSide(color: isGuard ? Colors.red : Colors.green),
          ),
          child: Text(
            isGuard ? "Remove" : "Make Guard",
            style: TextStyle(color: isGuard ? Colors.red : Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ) : const SizedBox(),
    );
  }

  // --- TAB 3: GUARD LOGS ---
  Widget _buildGuardLogsTab(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events').doc(widget.eventData['id'])
          .collection('attendance')
          .orderBy('lastEntry', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text("No activity logs yet."));

        var groupedLogs = _groupLogsByGuard(snapshot.data!.docs);

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedLogs.length,
          itemBuilder: (context, index) {
            String guardName = groupedLogs.keys.elementAt(index);
            var logs = groupedLogs[guardName]!;
            var entries = logs['Entries']!;
            var exits = logs['Exits']!;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
              ),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  child: const Icon(Icons.security, color: Colors.orange),
                ),
                title: Text(
                    guardName,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87
                    )
                ),
                subtitle: Text("In: ${entries.length} | Out: ${exits.length}", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                children: [
                  if (entries.isNotEmpty) ...[
                    _buildLogSectionHeader("ENTRIES (${entries.length})", Colors.green),
                    ...entries.map((log) => _buildLogItem(log, Icons.login, Colors.green)).toList(),
                  ],
                  if (exits.isNotEmpty) ...[
                    _buildLogSectionHeader("EXITS (${exits.length})", Colors.red),
                    ...exits.map((log) => _buildLogItem(log, Icons.logout, Colors.red)).toList(),
                  ],
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLogSectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: color.withOpacity(0.1),
      child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log, IconData icon, Color color) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 16, color: color),
      title: Text(log['studentName'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(log['studentId'] ?? '', style: const TextStyle(fontSize: 11)),
      trailing: Text(log['time'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  // --- Styled Widgets ---
  Widget _buildModernInput(TextEditingController c, String hint, IconData icon, ThemeData theme, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: hint,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Icon(icon, color: theme.primaryColor.withOpacity(0.8), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildGlassPicker(IconData icon, String value, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.primaryColor.withOpacity(0.8)),
            const SizedBox(width: 10),
            Text(value, style: TextStyle(color: theme.textTheme.bodyMedium?.color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
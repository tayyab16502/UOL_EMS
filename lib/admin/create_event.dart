import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore Import
import 'package:firebase_auth/firebase_auth.dart'; // Auth Import
import '../theme/theme.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> with TickerProviderStateMixin {
  int _currentStep = 1;
  bool _isLoading = false;
  late AnimationController _blobController;

  // Form Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locController = TextEditingController();
  final _feeController = TextEditingController();
  final _capacityController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  DateTime? _deadlineDate;

  // Event Type Selection
  String _selectedEventType = '';
  String _customEventTypeName = '';

  // Custom Type Dialog Controller
  final _customTypeController = TextEditingController();

  final List<Map<String, dynamic>> _eventTypes = [
    {'id': 'coding', 'label': 'Coding', 'icon': Icons.code, 'color': Colors.blue},
    {'id': 'seminar', 'label': 'Seminar', 'icon': Icons.group, 'color': Colors.green},
    {'id': 'workshop', 'label': 'Workshop', 'icon': Icons.build, 'color': Colors.orange},
    {'id': 'e_gaming', 'label': 'Gaming', 'icon': Icons.gamepad, 'color': Colors.purple},
    {'id': 'sports', 'label': 'Sports', 'icon': Icons.emoji_events, 'color': Colors.yellow},
    {'id': 'arts', 'label': 'Arts', 'icon': Icons.palette, 'color': Colors.pink},
    {'id': 'qawali', 'label': 'Qawali', 'icon': Icons.music_note, 'color': Colors.indigo},
    {'id': 'dinner', 'label': 'Dinner', 'icon': Icons.restaurant, 'color': Colors.red},
  ];

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blobController.dispose();
    _titleController.dispose(); _descController.dispose();
    _locController.dispose(); _feeController.dispose();
    _capacityController.dispose(); _customTypeController.dispose();
    super.dispose();
  }

  // --- ACTIONS ---
  void _nextStep() {
    if (_validateStep(_currentStep)) {
      if (_currentStep < 3) {
        setState(() => _currentStep++);
      } else {
        _submitEvent();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  bool _validateStep(int step) {
    if (step == 1) {
      if (_selectedEventType.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select an event type"), backgroundColor: Colors.red));
        return false;
      }
      return true;
    }
    if (step == 2) {
      if (_titleController.text.isEmpty || _descController.text.isEmpty || _capacityController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all details"), backgroundColor: Colors.red));
        return false;
      }
      return true;
    }
    if (step == 3) {
      if (_selectedDate == null || _selectedTime == null || _locController.text.isEmpty || _feeController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please complete schedule & fee"), backgroundColor: Colors.red));
        return false;
      }
      return true;
    }
    return false;
  }

  // --- SUBMIT LOGIC (UPDATED: FLAT STRUCTURE) ---
  Future<void> _submitEvent() async {
    setState(() => _isLoading = true);

    try {
      // 1. Get Current Admin User
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not logged in");
      }

      String adminDept = 'General'; // Default fallback

      // [FLAT STRUCTURE UPDATE]
      // Fetch Admin Profile directly from 'users' collection
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        // Get the department stored in the Admin's profile
        adminDept = data['department'] ?? 'General';
      }

      // 3. Prepare Date & Time
      final DateTime fullDate = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        _selectedTime!.hour, _selectedTime!.minute,
      );

      final DateTime deadline = _deadlineDate ?? fullDate.subtract(const Duration(days: 1));

      // 4. Create Data Map (With Correct Department)
      final eventData = {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'type': _selectedEventType == 'custom' ? _customEventTypeName : _selectedEventType,
        'capacity': int.tryParse(_capacityController.text) ?? 0,
        'location': _locController.text.trim(),
        'fee': int.tryParse(_feeController.text) ?? 0,
        'date': Timestamp.fromDate(fullDate),
        'time': _selectedTime!.format(context),
        'deadline': Timestamp.fromDate(deadline),
        'registeredStudents': [],
        'status': 'open',

        // --- Important Fields ---
        'department': adminDept, // Event belongs to the Admin's department
        'organizerUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 5. Save to Firestore (Events Collection remains same)
      await FirebaseFirestore.instance.collection('events').add(eventData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Event Published Successfully!"), backgroundColor: Colors.green));
      Navigator.pop(context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error creating event: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- DATE/TIME PICKERS ---
  Future<void> _pickDate(bool isDeadline) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
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
    if (picked != null) {
      setState(() {
        if (isDeadline) _deadlineDate = picked;
        else _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(primary: AppTheme.uolPrimary, onPrimary: Colors.white, onSurface: Colors.black),
              dialogBackgroundColor: Colors.white,
            ),
            child: child!,
          );
        }
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  // --- CUSTOM TYPE DIALOG ---
  void _showCustomTypeDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text("Add Custom Event Type", style: theme.textTheme.headlineSmall),
        content: TextField(
          controller: _customTypeController,
          style: theme.textTheme.bodyMedium,
          decoration: const InputDecoration(hintText: "Enter event type name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (_customTypeController.text.isNotEmpty) {
                setState(() {
                  _selectedEventType = 'custom';
                  _customEventTypeName = _customTypeController.text;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back, color: theme.iconTheme.color, size: 20),
                        label: Text("Back", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                      ),
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: theme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text("Create Event", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Progress Indicator
                _buildProgressIndicator(theme),

                // Main Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildCurrentStep(theme),
                    ),
                  ),
                ),

                // Navigation Buttons
                _buildBottomNavigation(theme),
              ],
            ),
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator(color: theme.primaryColor)),
            ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildProgressIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepCircle(1, "Type", theme),
          _buildStepLine(1, theme),
          _buildStepCircle(2, "Details", theme),
          _buildStepLine(2, theme),
          _buildStepCircle(3, "Schedule", theme),
        ],
      ),
    );
  }

  Widget _buildStepCircle(int step, String label, ThemeData theme) {
    bool isActive = _currentStep >= step;
    bool isCompleted = _currentStep > step;
    return Column(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: isActive ? theme.primaryColor : Colors.transparent,
            border: Border.all(color: isActive ? theme.primaryColor : Colors.grey),
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 8)] : [],
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text("$step", style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? theme.primaryColor : Colors.grey, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStepLine(int step, ThemeData theme) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        color: _currentStep > step ? theme.primaryColor : Colors.grey.withOpacity(0.3),
      ),
    );
  }

  Widget _buildCurrentStep(ThemeData theme) {
    switch (_currentStep) {
      case 1: return _buildStep1(theme);
      case 2: return _buildStep2(theme);
      case 3: return _buildStep3(theme);
      default: return Container();
    }
  }

  // STEP 1: Select Event Type
  Widget _buildStep1(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Select Event Type", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Choose the category that best describes your event", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: _eventTypes.length + 1,
          itemBuilder: (context, index) {
            if (index == _eventTypes.length) {
              bool isSelected = _selectedEventType == 'custom';
              return GestureDetector(
                onTap: _showCustomTypeDialog,
                child: _buildTypeCard(Icons.add, "Custom", theme.primaryColor, isSelected, theme, isCustom: true),
              );
            }
            final type = _eventTypes[index];
            bool isSelected = _selectedEventType == type['id'];
            return GestureDetector(
              onTap: () => setState(() { _selectedEventType = type['id']; _customEventTypeName = ''; }),
              child: _buildTypeCard(type['icon'], type['label'], type['color'], isSelected, theme),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTypeCard(IconData icon, String label, Color color, bool isSelected, ThemeData theme, {bool isCustom = false}) {
    Color textColor = isSelected
        ? color
        : (theme.brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.15) : theme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? color : theme.dividerColor, width: isSelected ? 2 : 1),
        boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8)] : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
          if (isCustom && _selectedEventType == 'custom')
            Text("($_customEventTypeName)", style: TextStyle(fontSize: 9, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // STEP 2: Details
  Widget _buildStep2(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Event Details", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Provide comprehensive information about your event", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),

        _buildInput(_titleController, "Event Title", Icons.title, theme),
        const SizedBox(height: 16),
        _buildInput(_descController, "Event Description", Icons.description, theme, maxLines: 5),
        const SizedBox(height: 16),
        _buildInput(_capacityController, "Maximum Capacity", Icons.people, theme, isNumber: true),
      ],
    );
  }

  // STEP 3: Schedule & Fee
  Widget _buildStep3(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Schedule & Fee", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text("Set the date, time, venue and fees", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(child: _buildDatePicker(false, theme)),
            const SizedBox(width: 16),
            Expanded(child: _buildTimePicker(theme)),
          ],
        ),
        const SizedBox(height: 16),
        _buildInput(_locController, "Venue / Location", Icons.location_on, theme),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildInput(_feeController, "Fee (PKR)", Icons.attach_money, theme, isNumber: true)),
            const SizedBox(width: 16),
            Expanded(child: _buildDatePicker(true, theme)),
          ],
        ),
      ],
    );
  }

  // --- Input Helpers ---
  Widget _buildInput(TextEditingController c, String hint, IconData icon, ThemeData theme, {int maxLines = 1, bool isNumber = false}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon, color: theme.primaryColor, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.inputDecorationTheme.fillColor,
      ),
    );
  }

  Widget _buildDatePicker(bool isDeadline, ThemeData theme) {
    String label = isDeadline ? "Deadline" : "Date";
    DateTime? date = isDeadline ? _deadlineDate : _selectedDate;
    Color textColor = date == null ? theme.hintColor : theme.textTheme.bodyMedium!.color!;

    return GestureDetector(
      onTap: () => _pickDate(isDeadline),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
            color: theme.inputDecorationTheme.fillColor,
            border: Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
            borderRadius: BorderRadius.circular(14)
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: theme.primaryColor),
            const SizedBox(width: 8),
            Text(date == null ? label : "${date.day}/${date.month}/${date.year}", style: TextStyle(color: textColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(ThemeData theme) {
    Color textColor = _selectedTime == null ? theme.hintColor : theme.textTheme.bodyMedium!.color!;

    return GestureDetector(
      onTap: _pickTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
            color: theme.inputDecorationTheme.fillColor,
            border: Border.all(color: theme.inputDecorationTheme.enabledBorder!.borderSide.color),
            borderRadius: BorderRadius.circular(14)
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 18, color: theme.primaryColor),
            const SizedBox(width: 8),
            Text(_selectedTime == null ? "Time" : _selectedTime!.format(context), style: TextStyle(color: textColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 1)
            OutlinedButton.icon(
              onPressed: _prevStep,
              icon: Icon(Icons.arrow_back, size: 18, color: theme.primaryColor),
              label: Text("Previous", style: TextStyle(color: theme.primaryColor)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), side: BorderSide(color: theme.primaryColor)),
            )
          else
            const SizedBox(),

          ElevatedButton.icon(
            onPressed: _nextStep,
            icon: Icon(_currentStep == 3 ? Icons.check : Icons.arrow_forward, color: Colors.white, size: 18),
            label: Text(_currentStep == 3 ? "Create Event" : "Next Step", style: const TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
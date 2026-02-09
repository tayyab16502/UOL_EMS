import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:intl/intl.dart';
import '../theme/theme.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;

  const EventDetailScreen({super.key, required this.eventData});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late AnimationController _timerController;

  bool _isFront = true;
  bool _showHint = true;
  bool _isLoadingUser = true;

  String _userName = "Loading...";
  String _regId = "...";
  String _userId = "";

  // Dynamic QR Data
  String _qrData = "";
  Timer? _qrRefreshTimer;

  // Real-time Attendance Stream
  Stream<DocumentSnapshot>? _attendanceStream;

  @override
  void initState() {
    super.initState();
    _secureScreen();
    _fetchUserDetails();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _timerController = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    _timerController.repeat();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  Future<void> _fetchUserDetails() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _userName = data['fullName'] ?? 'Student';
              _regId = data['studentId'] ?? 'N/A';
              _isLoadingUser = false;

              // Init Stream for Real-time Stamp
              _attendanceStream = FirebaseFirestore.instance
                  .collection('events').doc(widget.eventData['id'])
                  .collection('attendance').doc(_userId)
                  .snapshots();
            });
            _startLiveQR();
          }
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void _startLiveQR() {
    _generateQRData();
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _generateQRData();
    });
  }

  void _generateQRData() {
    if (!mounted) return;
    setState(() {
      _qrData = "${widget.eventData['id']}|$_userId|${DateTime.now().millisecondsSinceEpoch}";
    });
  }

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
    _controller.dispose();
    _timerController.dispose();
    _qrRefreshTimer?.cancel();
    _unsecureScreen();
    super.dispose();
  }

  void _flipCard() {
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    setState(() => _isFront = !_isFront);
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
        title: Text("Digital Ticket", style: theme.textTheme.headlineMedium),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),

          Center(
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  final angle = _animation.value * pi;
                  final transform = Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle);
                  return Transform(
                    transform: transform,
                    alignment: Alignment.center,
                    child: _animation.value < 0.5
                        ? _buildFrontCard(theme, isDark)
                        : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(pi),
                      child: _buildBackCard(theme),
                    ),
                  );
                },
              ),
            ),
          ),

          Positioned(
            bottom: 60, left: 0, right: 0,
            child: AnimatedOpacity(
              opacity: _showHint ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(20)),
                  child: const Text("Tap card to flip for QR", style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- FRONT SIDE (WITH REAL-TIME STAMP) ---
  Widget _buildFrontCard(ThemeData theme, bool isDark) {
    DateTime date = (widget.eventData['date'] is Timestamp)
        ? (widget.eventData['date'] as Timestamp).toDate()
        : DateTime.now();

    return Container(
      width: 320, height: 500,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
        border: Border.all(color: theme.primaryColor.withOpacity(0.3), width: 1),
      ),
      child: Stack(
        children: [
          // 1. Main Content
          Column(
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.uolPrimary, AppTheme.uolSecondary]), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Center(child: Icon(Icons.event_available, color: Colors.white.withOpacity(0.9), size: 50)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _isLoadingUser ? Center(child: CircularProgressIndicator(color: theme.primaryColor)) : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.eventData['title'] ?? 'Event', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
                      const SizedBox(height: 8),
                      Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text("Official Pass", style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12)))),
                      const Divider(height: 30),
                      _buildRow(Icons.person, "Attendee", _userName, theme),
                      const SizedBox(height: 12),
                      _buildRow(Icons.badge, "Reg ID", _regId, theme),
                      const SizedBox(height: 12),
                      _buildRow(Icons.calendar_today, "Date", DateFormat('dd MMM yyyy').format(date), theme),
                      const SizedBox(height: 12),
                      _buildRow(Icons.location_on, "Venue", widget.eventData['location'] ?? 'Unknown', theme),
                    ],
                  ),
                ),
              ),
              Container(
                height: 15, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.5), width: 2))),
                child: Center(child: Text("Admit One", style: TextStyle(fontSize: 8, color: Colors.grey.shade500, letterSpacing: 2))),
              ),
            ],
          ),

          // 2. REAL-TIME STAMP OVERLAY
          if (_attendanceStream != null)
            StreamBuilder<DocumentSnapshot>(
              stream: _attendanceStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();

                var data = snapshot.data!.data() as Map<String, dynamic>;
                String status = data['status'] ?? 'none';

                if (status == 'inside') {
                  return _buildStamp("ENTRY APPROVED", Colors.green);
                } else if (status == 'outside') {
                  return _buildStamp("EXIT APPROVED", Colors.deepOrange);
                }
                return const SizedBox();
              },
            ),
        ],
      ),
    );
  }

  // --- STAMP WIDGET ---
  Widget _buildStamp(String text, Color color) {
    return Positioned(
      top: 180,
      right: 20,
      child: Transform.rotate(
        angle: -0.2, // Tilted look
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(10),
            color: color.withOpacity(0.1), // Slightly transparent ink
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                DateFormat('hh:mm a').format(DateTime.now()), // Show scan time roughly
                style: TextStyle(
                    color: color.withOpacity(0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.bold
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- BACK SIDE (LIVE QR) ---
  Widget _buildBackCard(ThemeData theme) {
    return Container(
      width: 320, height: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2, color: Colors.black, size: 40),
          const SizedBox(height: 20),
          Text("Scan at Entrance", style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 30),

          _isLoadingUser
              ? const CircularProgressIndicator()
              : QrImageView(
            data: _qrData,
            version: QrVersions.auto,
            size: 200.0,
            backgroundColor: Colors.white,
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AnimatedBuilder(
                animation: _timerController,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: _timerController.value,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                    minHeight: 6,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text("Live Code: Updates every 5s", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),

          const SizedBox(height: 30),
          Text("Ticket ID: ${(widget.eventData['id'] ?? '').toString().substring(0, 5).toUpperCase()}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.primaryColor),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6))), Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)])),
      ],
    );
  }
}
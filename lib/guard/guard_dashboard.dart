import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore
import 'package:intl/intl.dart'; // Date Formatting
import '../theme/theme.dart';
import 'scan_ticket.dart';

class GuardDashboard extends StatefulWidget {
  final String guardEmail;
  const GuardDashboard({super.key, required this.guardEmail});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> with SingleTickerProviderStateMixin {
  late AnimationController _blobController;
  final DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blobController.dispose();
    super.dispose();
  }

  // Navigate to Scanner
  void _startScanning(String eventId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanTicketScreen(eventId: eventId),
      ),
    );
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
        // CHANGED: Back Button allows returning to Student Dashboard
        leading: BackButton(
            color: Colors.white,
            onPressed: () => Navigator.pop(context)
        ),
        title: Text("Guard Panel", style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22, fontWeight: FontWeight.bold)),
        centerTitle: true,
        // NO LOGOUT BUTTON HERE (Unified Flow)
      ),
      body: Stack(
        children: [
          // Background
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness)))),
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.uolSecondary, AppTheme.uolPrimary]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: theme.primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Guard Mode Active", style: TextStyle(color: Colors.white70, fontSize: 14)),
                                SizedBox(height: 4),
                                Text("Scanner Ready", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.security, color: Colors.white, size: 28),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  Text("Available Events", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // 2. Active Events Stream (Real-Time)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('events')
                    // Logic: Show events from yesterday onwards (to cover ongoing events)
                        .where('date', isGreaterThan: Timestamp.fromDate(_now.subtract(const Duration(days: 1))))
                        .orderBy('date')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(child: Text("No active events found.", style: theme.textTheme.bodyMedium));
                      }

                      var events = snapshot.data!.docs;

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          var doc = events[index];
                          var data = doc.data() as Map<String, dynamic>;
                          DateTime date = (data['date'] as Timestamp).toDate();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: theme.cardColor.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: theme.primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                        child: Icon(Icons.event_note, color: theme.primaryColor),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(data['title'] ?? 'Event', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                                                const SizedBox(width: 4),
                                                Text(data['location'] ?? 'Unknown', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                                const SizedBox(width: 4),
                                                Text("${DateFormat('dd MMM').format(date)} • ${data['time']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _startScanning(doc.id),
                                      icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                                      label: const Text("Start Scanning", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                        elevation: 4,
                                        shadowColor: Colors.orange.withOpacity(0.4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(top: top, left: left, right: right, bottom: bottom, child: AnimatedBuilder(animation: _blobController, builder: (_, __) => Transform.scale(scale: 1.0 + (sin(_blobController.value * 2 * pi + offset) * 0.2), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100)])))));
  }
}
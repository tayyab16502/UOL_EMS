import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/theme.dart';

class DepartmentControlScreen extends StatefulWidget {
  const DepartmentControlScreen({super.key});

  @override
  State<DepartmentControlScreen> createState() => _DepartmentControlScreenState();
}

class _DepartmentControlScreenState extends State<DepartmentControlScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blobController;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Department Control"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppTheme.getGradient(theme.brightness),
              ),
            ),
          ),

          // 2. Animated Blobs
          _buildAnimatedBlob(top: size.height * 0.1, right: -100, color: theme.primaryColor.withOpacity(0.15), size: 300, offset: 0.2),
          _buildAnimatedBlob(bottom: size.height * 0.1, left: -100, color: AppTheme.uolSecondary.withOpacity(0.15), size: 300, offset: 0.7),

          // 3. Content
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('departments').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: theme.primaryColor));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.apartment, size: 60, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 10),
                        Text("No Departments Found", style: theme.textTheme.headlineSmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                var docs = snapshot.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = (data['name'] ?? docs[index].id).toString().trim();
                    bool isLocked = data['isLocked'] ?? false;

                    // BOSS LOGIC
                    bool isCS = name == 'Computer Science' || name == 'CS';

                    return _buildDepartmentCard(
                      theme: theme,
                      name: name,
                      isLocked: isLocked,
                      isCS: isCS,
                      onToggle: (val) async {
                        await FirebaseFirestore.instance.collection('departments').doc(docs[index].id).update({'isLocked': val});
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard({
    required ThemeData theme,
    required String name,
    required bool isLocked,
    required bool isCS,
    required Function(bool) onToggle,
  }) {
    Color cardColor = isCS
        ? theme.primaryColor.withOpacity(0.15)
        : theme.cardColor.withOpacity(0.7);

    Color borderColor = isCS
        ? theme.primaryColor
        : (isLocked ? Colors.red.withOpacity(0.5) : theme.dividerColor);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isCS ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: isCS ? theme.primaryColor.withOpacity(0.1) : Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              activeColor: Colors.red, // Red for Locked
              activeTrackColor: Colors.red.withOpacity(0.3),
              inactiveThumbColor: Colors.green, // Green for Active
              inactiveTrackColor: Colors.green.withOpacity(0.3),

              title: Text(
                name,
                maxLines: 1, // Prevent long names from breaking UI
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isCS ? theme.primaryColor : theme.textTheme.bodyLarge?.color,
                ),
              ),

              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      isCS ? Icons.shield : (isLocked ? Icons.lock : Icons.lock_open),
                      size: 14,
                      color: isCS ? theme.primaryColor : (isLocked ? Colors.red : Colors.green),
                    ),
                    const SizedBox(width: 6),
                    // [FIXED]: Wrapped in Flexible to prevent overflow
                    Flexible(
                      child: Text(
                        isCS ? "MASTER CONTROL" : (isLocked ? "LOCKED" : "ACTIVE"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCS ? theme.primaryColor : (isLocked ? Colors.red : Colors.green),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCS
                      ? theme.primaryColor.withOpacity(0.2)
                      : (isLocked ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCS ? Icons.admin_panel_settings : Icons.apartment,
                  color: isCS
                      ? theme.primaryColor
                      : (isLocked ? Colors.red : Colors.green),
                ),
              ),

              // Prevent CS from being locked
              value: isLocked,
              onChanged: isCS ? null : onToggle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBlob({required double size, required Color color, required double offset, double? top, double? left, double? right, double? bottom}) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
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
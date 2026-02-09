import 'package:flutter/material.dart';
import '../theme/theme.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  // Mock Users List
  final List<Map<String, dynamic>> _users = [
    {'name': 'Ali Khan', 'email': 'ali@uol.edu.pk', 'role': 'Student'},
    {'name': 'Bilal Ahmed', 'email': 'bilal@uol.edu.pk', 'role': 'Guard'},
    {'name': 'Zainab Bibi', 'email': 'zainab@uol.edu.pk', 'role': 'Student'},
  ];

  void _toggleRole(int index) {
    setState(() {
      if (_users[index]['role'] == 'Student') {
        _users[index]['role'] = 'Guard';
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User promoted to Guard"), backgroundColor: Colors.green));
      } else {
        _users[index]['role'] = 'Student';
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User demoted to Student"), backgroundColor: Colors.orange));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Manage Staff", style: theme.textTheme.headlineSmall),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: theme.iconTheme.color),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppTheme.getGradient(theme.brightness))),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _users.length,
          itemBuilder: (context, index) {
            final user = _users[index];
            bool isGuard = user['role'] == 'Guard';

            return Card(
              color: theme.cardColor,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isGuard ? theme.primaryColor : Colors.grey,
                  child: Icon(isGuard ? Icons.security : Icons.person, color: Colors.white),
                ),
                title: Text(user['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(user['email']),
                trailing: Switch(
                  value: isGuard,
                  activeColor: theme.primaryColor,
                  onChanged: (val) => _toggleRole(index),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
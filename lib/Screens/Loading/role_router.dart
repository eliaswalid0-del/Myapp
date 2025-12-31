import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Admin/admin_dashboard.dart';
import '../Manager/manager_dashboard.dart';
import '../ops_manager/ops_manager_dashboard.dart';
import '../Employee/employee_dashboard.dart';
import 'loading_screen.dart';

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  Future<String> _getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'employee'; // Default fallback

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        String? role = doc.data()?['role'];
        
        // If no role found, default to employee and update the document
        if (role == null || role.isEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'email': user.email,
            'role': 'employee',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return 'employee';
        }
        
        return role;
      } else {
        // User document doesn't exist, create it with employee role
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'role': 'employee',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return 'employee';
      }
    } catch (e) {
      print('Error getting user role: $e');
      return 'employee'; // Default fallback on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getUserRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (snapshot.hasError) {
          return const Center(child: Text("Error loading user data"));
        }

        final role = snapshot.data ?? 'employee'; // Default fallback
        final normalized = role.toLowerCase();

        switch (normalized) {
          case "admin":
            return AdminDashboard();
          case "manager":
            return ManagerDashboard();
          case "ops_manager":
            return OpsManagerDashboard();
          case "employee":
            return EmployeeDashboard();
          default:
            return EmployeeDashboard(); // Default fallback
        }
      },
    );
  }
}
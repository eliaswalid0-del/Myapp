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

  Future<String?> _getUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    return doc.data()?['role'];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getUserRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (!snapshot.hasData) {
          return const Center(child: Text("Role not found"));
        }

        final role = snapshot.data;
        if (role == null) {
          return const Center(child: Text("Role not found"));
        }

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
            return const Center(child: Text("Unknown role"));
        }
      },
    );
  }
}

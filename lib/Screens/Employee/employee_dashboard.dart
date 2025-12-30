```dart
import 'package:flutter/material.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Welcome to the Employee Dashboard',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
```
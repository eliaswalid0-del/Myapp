import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'Screens/auth/login_screen.dart';
import 'Screens/Loading/role_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyC--Sxv9sX7wA5ClAudMjU7vt2z-F6k0eY",
      authDomain: "studio-6313173084-d2ab9.firebaseapp.com",
      projectId: "studio-6313173084-d2ab9",
      storageBucket: "studio-6313173084-d2ab9.firebasestorage.app",
      messagingSenderId: "875873842774",
      appId: "1:875873842774:web:2b51d39f7ef1305d052df7",
    ),
  );

  runApp(const FoodSafeTrackApp());
}

class FoodSafeTrackApp extends StatelessWidget {
  const FoodSafeTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const LoginScreen();
          }
          return const RoleRouter();
        },
      ),
    );
  }
}

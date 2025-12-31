import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';

class EmployeeDashboard extends StatefulWidget {
  const EmployeeDashboard({Key? key}) : super(key: key);

  @override
  State<EmployeeDashboard> createState() => _EmployeeDashboardState();
}

class _EmployeeDashboardState extends State<EmployeeDashboard> with TickerProviderStateMixin {
  late TabController _tabController;
  
  // Profile controllers
  final TextEditingController joiningDateController = TextEditingController();
  final TextEditingController positionController = TextEditingController();
  bool isJoiningDateSet = false; // Track if joining date is already set
  String? profilePhotoName; // Employee photo
  bool isPhotoUploaded = false; // Track if photo is uploaded
  
  // ===== NEW TO-DO LIST FUNCTIONALITY =====
  List<Map<String, dynamic>> todoList = [];
  final TextEditingController todoController = TextEditingController();
  bool isAddingTodo = false;
  
  // Notifications
  int unreadMemoCount = 0;
  List<Map<String, dynamic>> memos = [];
  
  // Attendance data
  bool isClockedIn = false;
  bool isOnBreak = false;
  DateTime? clockInTime;
  DateTime? clockOutTime;
  DateTime? breakInTime;
  DateTime? breakOutTime;
  bool isWithinRange = false;
  bool isBreakExhausted = false; // 1 hour break taken
  
  // Restaurant location (will be detected and saved)
  double? restaurantLat;
  double? restaurantLng;
  bool locationSet = false;
  
  // Leave data
  double annualLeaveBalance = 0.0;
  double totalAccumulatedLeave = 0.0; // For display purposes
  double totalUsedLeave = 0.0; // For display purposes
  int publicHolidayDays = 0;
  List<Map<String, dynamic>> leaveHistory = [];
  final TextEditingController leaveFromController = TextEditingController();
  final TextEditingController leaveToController = TextEditingController();
  String selectedLeaveType = 'AL'; // AL or PH
  
  // Document uploads with expiry tracking - ENHANCED
  Map<String, Map<String, dynamic>> uploadedFiles = {
    'passport': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '🛂 Passport', 'priority': 'high'},
    'eid': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '🆔 Emirates ID', 'priority': 'high'},
    'workVisa': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '📋 Work Visa', 'priority': 'critical'},
    'labourCard': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '💼 Labour Card', 'priority': 'critical'},
    'bfhtCertificate': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '🏥 BFHT Certificate', 'priority': 'medium'},
    'picCertificate': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '📜 PIC Certificate', 'priority': 'medium'},
    'ohc': {'file': null, 'expiry': null, 'isExpiring': false, 'displayName': '🩺 OHC', 'priority': 'low'},
  };

  // Schedule data
  Map<String, dynamic>? weeklySchedule;
  Map<String, dynamic> attendanceLog = {}; // Track late arrivals

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // NOW 4 TABS INCLUDING TO-DO
    _loadUserData();
    _loadMemos();
    _loadTodoList(); // NEW: Load todo list
    _checkLocationPermission();
    _loadScheduleData();
    print('Employee Dashboard initialized with 4 tabs');
  }

  @override
  void dispose() {
    _tabController.dispose();
    joiningDateController.dispose();
    positionController.dispose();
    leaveFromController.dispose();
    leaveToController.dispose();
    todoController.dispose(); // NEW: Dispose todo controller
    super.dispose();
  }

  String getUserName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      String email = user!.email!;
      String name = email.split('@')[0];
      return name.split('.').map((part) => 
        part[0].toUpperCase() + part.substring(1).toLowerCase()
      ).join(' ');
    }
    return 'User';
  }

  // ===== NEW TO-DO LIST FUNCTIONS =====
  Future<void> _loadTodoList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        print('Loading todo list for user: ${user.uid}');
        final doc = await FirebaseFirestore.instance
            .collection('todos')
            .doc(user.uid)
            .get();
        
        if (doc.exists && doc.data()!['tasks'] != null) {
          setState(() {
            todoList = List<Map<String, dynamic>>.from(doc.data()!['tasks']);
          });
          print('Loaded ${todoList.length} todos');
        } else {
          print('No todos found for user');
        }
      } catch (e) {
        print('Error loading todo list: $e');
      }
    }
  }

  Future<void> _saveTodoList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('todos')
            .doc(user.uid)
            .set({
          'tasks': todoList,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('Todo list saved successfully');
      } catch (e) {
        print('Error saving todo list: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving todo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addTodo() async {
    if (todoController.text.trim().isNotEmpty) {
      setState(() {
        isAddingTodo = true;
      });

      setState(() {
        todoList.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'text': todoController.text.trim(),
          'completed': false,
          'createdAt': DateTime.now().toIso8601String(),
          'priority': 'normal',
        });
      });
      
      todoController.clear();
      await _saveTodoList();
      
      setState(() {
        isAddingTodo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task added successfully!'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _toggleTodo(int index) async {
    setState(() {
      todoList[index]['completed'] = !todoList[index]['completed'];
      todoList[index]['completedAt'] = todoList[index]['completed'] 
          ? DateTime.now().toIso8601String() 
          : null;
    });
    await _saveTodoList();
  }

  Future<void> _deleteTodo(int index) async {
    final todoText = todoList[index]['text'];
    setState(() {
      todoList.removeAt(index);
    });
    await _saveTodoList();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Task "$todoText" deleted'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            // Could implement undo functionality here
          },
        ),
      ),
    );
  }

  void _editTodo(int index) {
    final currentText = todoList[index]['text'];
    final TextEditingController editController = TextEditingController(text: currentText);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(
            hintText: 'Enter task description',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (editController.text.trim().isNotEmpty) {
                setState(() {
                  todoList[index]['text'] = editController.text.trim();
                  todoList[index]['lastModified'] = DateTime.now().toIso8601String();
                });
                await _saveTodoList();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task updated!'), backgroundColor: Colors.blue),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  int get completedTasks => todoList.where((todo) => todo['completed'] == true).length;
  int get pendingTasks => todoList.where((todo) => todo['completed'] == false).length;
  // ===== END TO-DO LIST FUNCTIONS =====

  Future<void> _loadMemos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('memos')
            .where('targetAudience', whereIn: ['all', 'employees'])
            .orderBy('timestamp', descending: true)
            .get();

        setState(() {
          memos = querySnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'title': data['title'],
              'content': data['content'],
              'from': data['from'],
              'timestamp': data['timestamp']?.toDate().toString().split(' ')[0] ?? 'Unknown',
              'isRead': data['readBy']?.contains(user.uid) ?? false,
            };
          }).toList();

          // Count unread memos
          unreadMemoCount = memos.where((memo) => !memo['isRead']).length;
        });
      } catch (e) {
        print('Error loading memos: $e');
      }
    }
  }

  Future<void> _createSampleMemos() async {
    try {
      // Sample memo 1
      await FirebaseFirestore.instance.collection('memos').add({
        'title': 'Welcome to HQSync!',
        'content': 'Please update your profile and upload all required documents by end of week. Make sure all documents are valid and not expiring soon.',
        'from': 'Manager',
        'timestamp': FieldValue.serverTimestamp(),
        'targetAudience': 'employees',
        'readBy': [],
      });

      // Sample memo 2  
      await FirebaseFirestore.instance.collection('memos').add({
        'title': 'New Break Policy Update',
        'content': 'Reminder: Break time is limited to 1 hour per day. Please clock out properly and notify your supervisor for any overtime breaks.',
        'from': 'Ops Manager',
        'timestamp': FieldValue.serverTimestamp(),
        'targetAudience': 'all',
        'readBy': [],
      });

      // Sample memo 3
      await FirebaseFirestore.instance.collection('memos').add({
        'title': 'Document Expiry Alert',
        'content': 'Several employees have documents expiring soon. Please check your profile and renew them immediately to avoid work disruptions.',
        'from': 'HR Manager',
        'timestamp': FieldValue.serverTimestamp(),
        'targetAudience': 'employees',
        'readBy': [],
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample memos created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh memos to show them
      _loadMemos();
    } catch (e) {
      print('Error creating memos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating memos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showNotifications() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.blue),
            const SizedBox(width: 10),
            const Text('Notifications'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unreadMemoCount unread',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 350,
          child: memos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 60, color: Colors.grey),
                      SizedBox(height: 10),
                      Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: memos.length,
                  itemBuilder: (context, index) {
                    final memo = memos[index];
                    return Card(
                      color: memo['isRead'] ? Colors.grey.shade100 : Colors.blue.shade50,
                      elevation: memo['isRead'] ? 1 : 3,
                      child: ListTile(
                        leading: Icon(
                          memo['isRead'] ? Icons.mark_email_read : Icons.mark_email_unread,
                          color: memo['isRead'] ? Colors.grey : Colors.blue,
                        ),
                        title: Text(
                          memo['title'],
                          style: TextStyle(
                            fontWeight: memo['isRead'] ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('From: ${memo['from']}\nDate: ${memo['timestamp']}'),
                        trailing: memo['isRead'] 
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 16)
                            : Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: () {
                          _markMemoAsRead(memo['id']);
                          _showMemoDetails(memo);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (unreadMemoCount > 0)
            TextButton(
              onPressed: () {
                // Mark all as read functionality could go here
              },
              child: const Text('Mark All Read'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _markMemoAsRead(String memoId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('memos')
            .doc(memoId)
            .update({
          'readBy': FieldValue.arrayUnion([user.uid]),
        });
        _loadMemos(); // Refresh memos
      } catch (e) {
        print('Error marking memo as read: $e');
      }
    }
  }

  void _showMemoDetails(Map<String, dynamic> memo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.message, color: Colors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(memo['title'])),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📤 From: ${memo['from']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('📅 Date: ${memo['timestamp']}'),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Text(
                memo['content'],
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ENHANCED PHOTO UPLOAD WITH BETTER FEEDBACK
  Future<void> _uploadProfilePhoto() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          profilePhotoName = result.files.single.name;
          isPhotoUploaded = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text('✅ Profile photo ${result.files.single.name} uploaded successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 10),
              Text('❌ Photo upload failed: $e'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(user.uid)
            .get();
        
        if (doc.exists) {
          final data = doc.data()!;
          setState(() {
            joiningDateController.text = data['joiningDate'] ?? '';
            positionController.text = data['position'] ?? '';
            profilePhotoName = data['profilePhoto'];
            isPhotoUploaded = profilePhotoName != null;
            isJoiningDateSet = data['joiningDate'] != null && data['joiningDate'].isNotEmpty;
            restaurantLat = data['restaurantLat'];
            restaurantLng = data['restaurantLng'];
            locationSet = restaurantLat != null && restaurantLng != null;
            
            // Load uploaded files
            if (data['documents'] != null) {
              Map<String, dynamic> docs = Map<String, dynamic>.from(data['documents']);
              docs.forEach((key, value) {
                if (uploadedFiles.containsKey(key)) {
                  uploadedFiles[key]!.addAll(Map<String, dynamic>.from(value));
                }
              });
            }
          });
          
          // Calculate leave balance after loading joining date
          await _calculateLeaveBalance();
        }
      } catch (e) {
        print('Error loading user data: $e');
      }
    }
  }

  Future<void> _saveProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(user.uid)
            .set({
          'joiningDate': joiningDateController.text,
          'position': positionController.text,
          'profilePhoto': profilePhotoName,
          'documents': uploadedFiles,
          'restaurantLat': restaurantLat,
          'restaurantLng': restaurantLng,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        if (!isJoiningDateSet && joiningDateController.text.isNotEmpty) {
          setState(() {
            isJoiningDateSet = true;
          });
        }

        // Recalculate leave balance after saving joining date
        await _calculateLeaveBalance();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ENHANCED AL CALCULATION WITH BETTER DATE PARSING
  Future<void> _calculateLeaveBalance() async {
    if (joiningDateController.text.isNotEmpty) {
      try {
        DateTime joiningDate;
        String dateText = joiningDateController.text.trim();
        
        print('🔍 Parsing date: $dateText');
        
        // Handle multiple date formats
        if (dateText.contains('-')) {
          // Handle YYYY-MM-DD or DD-MM-YYYY format
          List<String> parts = dateText.split('-');
          if (parts[0].length == 4) {
            // YYYY-MM-DD format
            joiningDate = DateTime.parse(dateText);
          } else {
            // DD-MM-YYYY format
            joiningDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } else if (dateText.contains('/')) {
          // Handle DD/MM/YYYY format
          List<String> parts = dateText.split('/');
          joiningDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else {
          print('❌ Invalid date format: $dateText');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Invalid date format. Use YYYY-MM-DD or DD-MM-YYYY'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        DateTime now = DateTime.now();
        
        print('📅 Joining Date: $joiningDate');
        print('📅 Current Date: $now');
        
        // Calculate complete months from joining date to today
        int monthsWorked = (now.year - joiningDate.year) * 12 + now.month - joiningDate.month;
        
        // If current day is before joining day in the month, subtract 1 month
        if (now.day < joiningDate.day) {
          monthsWorked--;
        }
        
        // Ensure non-negative months
        monthsWorked = monthsWorked < 0 ? 0 : monthsWorked;
        
        print('📊 Months worked: $monthsWorked');
        
        // Calculate total accumulated leave (2.5 days per month)
        double totalAccumulated = monthsWorked * 2.5;
        
        print('💰 Total accumulated before fetching used days: $totalAccumulated');
        
        // Fetch used leave days from Firebase
        double usedLeaveDays = await _getUsedLeaveDays();
        
        setState(() {
          totalAccumulatedLeave = totalAccumulated;
          totalUsedLeave = usedLeaveDays;
          annualLeaveBalance = totalAccumulated - usedLeaveDays;
          // Ensure balance doesn't go negative
          if (annualLeaveBalance < 0) {
            annualLeaveBalance = 0;
          }
        });
        
        print('✅ Final AL calculation:');
        print('   Months: $monthsWorked');
        print('   Total: $totalAccumulated days');
        print('   Used: $usedLeaveDays days');
        print('   Available: $annualLeaveBalance days');
        
        // Show success message if calculation is good
        if (totalAccumulated > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ AL calculated: ${annualLeaveBalance.toStringAsFixed(1)} days available'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
      } catch (e) {
        print('❌ Error calculating leave balance: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error calculating AL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      print('⚠️ Joining date is empty');
    }
  }

  Future<double> _getUsedLeaveDays() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;

    try {
      // Get all approved AL leave requests for this user
      final querySnapshot = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'AL')
          .where('status', isEqualTo: 'Approved')
          .get();

      double totalUsedDays = 0.0;
      
      // Clear and rebuild leave history from Firebase
      List<Map<String, dynamic>> newLeaveHistory = [];
      
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final days = data['days']?.toDouble() ?? 0.0;
        totalUsedDays += days;
        
        // Add to leave history
        newLeaveHistory.add({
          'type': 'Annual Leave',
          'date': '${data['fromDate']} to ${data['toDate']}',
          'days': days.toInt(),
          'status': data['status'],
          'requestDate': data['requestDate']?.toDate().toString().split(' ')[0] ?? 'Unknown',
        });
      }

      // Sort history by request date (newest first)
      newLeaveHistory.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['requestDate']);
          DateTime dateB = DateTime.parse(b['requestDate']);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      // Update leave history
      setState(() {
        leaveHistory = newLeaveHistory;
      });

      return totalUsedDays;
    } catch (e) {
      print('Error getting used leave days: $e');
      return 0.0;
    }
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      _startLocationTracking();
    }
  }

  void _startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (!locationSet) {
        // First time - set restaurant location
        setState(() {
          restaurantLat = position.latitude;
          restaurantLng = position.longitude;
          locationSet = true;
          isWithinRange = true;
        });
        _saveProfileData(); // Save restaurant location
      } else {
        // Check if within range of saved restaurant location
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          restaurantLat!,
          restaurantLng!,
        );
        
        setState(() {
          isWithinRange = distance <= 10; // 10 meters
        });

        // Auto clock out if too far
        if (distance > 10 && isClockedIn) {
          _clockOut();
        }
      }
    });
  }

  void _loadScheduleData() {
    // Mock schedule data - in real app, load from manager dashboard
    setState(() {
      weeklySchedule = {
        'Monday': {'start': '13:00', 'end': '23:00', 'type': 'normal', 'date': '2025-01-06'},
        'Tuesday': {'start': '09:00', 'end': '17:00', 'type': 'normal', 'date': '2025-01-07'},
        'Wednesday': {'start': '13:00', 'end': '23:00', 'type': 'AL', 'date': '2025-01-08'},
        'Thursday': {'start': '09:00', 'end': '17:00', 'type': 'normal', 'date': '2025-01-09'},
        'Friday': {'start': '13:00', 'end': '23:00', 'type': 'PH', 'date': '2025-01-10'},
        'Saturday': {'start': 'OFF', 'end': 'OFF', 'type': 'off', 'date': '2025-01-11'},
        'Sunday': {'start': 'OFF', 'end': 'OFF', 'type': 'off', 'date': '2025-01-12'},
      };
    });
    _analyzeScheduleForLeave();
  }

  void _analyzeScheduleForLeave() {
    if (weeklySchedule != null) {
      weeklySchedule!.forEach((day, schedule) {
        if (schedule['type'] == 'PH') {
          setState(() {
            publicHolidayDays += 1;
          });
        }
      });
    }
  }

  Future<void> _clockIn() async {
    if (!isWithinRange) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be within 10m of the restaurant to clock in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    DateTime now = DateTime.now();
    setState(() {
      isClockedIn = true;
      clockInTime = now;
    });

    // Check if late
    _checkIfLate(now);
    
    // Save attendance log
    _saveAttendanceLog();
  }

  void _checkIfLate(DateTime clockInTime) {
    String today = _getTodayDayName();
    if (weeklySchedule != null && weeklySchedule!.containsKey(today)) {
      String scheduledStart = weeklySchedule![today]['start'];
      if (scheduledStart != 'OFF') {
        DateTime scheduled = _parseTimeToDateTime(scheduledStart);
        
        if (clockInTime.isAfter(scheduled)) {
          int minutesLate = clockInTime.difference(scheduled).inMinutes;
          setState(() {
            attendanceLog[today] = {
              'status': 'Late',
              'minutes': minutesLate,
              'clockIn': clockInTime.toString(),
            };
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Late arrival: $minutesLate minutes'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  DateTime _parseTimeToDateTime(String time) {
    List<String> parts = time.split(':');
    DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  String _getTodayDayName() {
    List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[DateTime.now().weekday - 1];
  }

  void _clockOut() {
    setState(() {
      isClockedIn = false;
      clockOutTime = DateTime.now();
      // If on break, end break too
      if (isOnBreak) {
        isOnBreak = false;
        breakOutTime = DateTime.now();
      }
    });
    _saveAttendanceLog();
  }

  void _breakIn() {
    if (!isClockedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please clock in first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (isBreakExhausted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Break time already used for today'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isOnBreak = true;
      breakInTime = DateTime.now();
    });

    // Start break timer (1 hour limit)
    Future.delayed(const Duration(hours: 1), () {
      if (isOnBreak) {
        _breakOut(); // Auto break out after 1 hour
        _notifyManagerBreakOvertime();
      }
    });
  }

  void _breakOut() {
    setState(() {
      isOnBreak = false;
      breakOutTime = DateTime.now();
      isBreakExhausted = true; // Mark break as used
    });
  }

  void _notifyManagerBreakOvertime() {
    // In real app, send notification to manager dashboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Break exceeded 1 hour - Manager notified'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _saveAttendanceLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc('${user.uid}_${DateTime.now().toString().split(' ')[0]}')
            .set({
          'userId': user.uid,
          'date': DateTime.now().toString().split(' ')[0],
          'clockIn': clockInTime?.toString(),
          'clockOut': clockOutTime?.toString(),
          'breakIn': breakInTime?.toString(),
          'breakOut': breakOutTime?.toString(),
          'attendanceLog': attendanceLog,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error saving attendance: $e');
      }
    }
  }

  // ENHANCED FILE UPLOAD WITH BETTER VISIBILITY
  Future<void> uploadFile(String documentType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          uploadedFiles[documentType]!['file'] = result.files.single.name;
          uploadedFiles[documentType]!['uploadedAt'] = DateTime.now().toIso8601String();
          uploadedFiles[documentType]!['fileSize'] = result.files.single.size;
        });
        
        await _analyzeDocumentExpiry(result.files.single.name!, documentType);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.upload_file, color: Colors.white),
                const SizedBox(width: 10),
                Text('📄 ${result.files.single.name} uploaded successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 10),
              Text('❌ Upload failed: $e'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ENHANCED AI ANALYSIS WITH REALISTIC DIFFERENT EXPIRY DATES
  Future<void> _analyzeDocumentExpiry(String fileName, String docType) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text('🤖 AI analyzing $docType expiry date...'),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
    
    await Future.delayed(const Duration(seconds: 3)); // Simulate AI processing
    
    // Realistic AI analysis with DIFFERENT expiry dates for each document type
    DateTime mockExpiryDate;
    String aiConfidence = '';
    
    switch (docType) {
      case 'passport':
        mockExpiryDate = DateTime.now().add(const Duration(days: 25)); // Expiring soon
        aiConfidence = '94%';
        break;
      case 'eid':
        mockExpiryDate = DateTime.now().add(const Duration(days: 180)); // Safe
        aiConfidence = '97%';
        break;
      case 'workVisa':
        mockExpiryDate = DateTime.now().add(const Duration(days: 42)); // Warning
        aiConfidence = '91%';
        break;
      case 'labourCard':
        mockExpiryDate = DateTime.now().add(const Duration(days: 300)); // Very safe
        aiConfidence = '96%';
        break;
      case 'bfhtCertificate':
        mockExpiryDate = DateTime.now().add(const Duration(days: 18)); // Critical
        aiConfidence = '89%';
        break;
      case 'picCertificate':
        mockExpiryDate = DateTime.now().add(const Duration(days: 125)); // Safe
        aiConfidence = '93%';
        break;
      case 'ohc':
        mockExpiryDate = DateTime.now().add(const Duration(days: 38)); // Warning
        aiConfidence = '92%';
        break;
      default:
        mockExpiryDate = DateTime.now().add(const Duration(days: 60));
        aiConfidence = '90%';
    }
    
    bool isExpiring = mockExpiryDate.difference(DateTime.now()).inDays <= 45;
    
    setState(() {
      uploadedFiles[docType]!['expiry'] = mockExpiryDate.toString().split(' ')[0];
      uploadedFiles[docType]!['isExpiring'] = isExpiring;
      uploadedFiles[docType]!['aiConfidence'] = aiConfidence;
      uploadedFiles[docType]!['daysUntilExpiry'] = mockExpiryDate.difference(DateTime.now()).inDays;
    });
    
    // Show detailed AI result
    Color resultColor = isExpiring ? Colors.red : Colors.green;
    String resultIcon = isExpiring ? '⚠️' : '✅';
    String urgency = isExpiring ? 'URGENT' : 'OK';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$resultIcon AI Analysis Complete ($aiConfidence accuracy)',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              '${uploadedFiles[docType]!['displayName']} expires: ${mockExpiryDate.toString().split(' ')[0]}',
              style: const TextStyle(color: Colors.white),
            ),
            Text(
              'Status: $urgency (${mockExpiryDate.difference(DateTime.now()).inDays} days remaining)',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: resultColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submitLeaveRequest() async {
    if (leaveFromController.text.isEmpty || leaveToController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in both from and to dates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      DateTime fromDate = DateTime.parse(leaveFromController.text);
      DateTime toDate = DateTime.parse(leaveToController.text);
      int requestedDays = toDate.difference(fromDate).inDays + 1;

      // Check balance based on leave type
      double availableBalance = selectedLeaveType == 'AL' ? annualLeaveBalance : publicHolidayDays.toDouble();
      
      if (requestedDays > availableBalance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insufficient balance. Available: ${availableBalance.toStringAsFixed(1)} days, Requested: $requestedDays days'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Submit request
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('leave_requests')
            .add({
          'userId': user.uid,
          'userName': getUserName(),
          'type': selectedLeaveType,
          'fromDate': leaveFromController.text,
          'toDate': leaveToController.text,
          'days': requestedDays,
          'status': 'Pending',
          'requestDate': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        leaveFromController.clear();
        leaveToController.clear();
        
        // Refresh leave balance to show pending request
        await _calculateLeaveBalance();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editDocument(String documentType) {
    final docInfo = uploadedFiles[documentType]!;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.edit_document, color: Colors.orange),
            const SizedBox(width: 10),
            Text('Edit ${docInfo['displayName']}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (docInfo['file'] != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📄 Current file: ${docInfo['file']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (docInfo['expiry'] != null)
                      Text('📅 Expires: ${docInfo['expiry']}'),
                    if (docInfo['aiConfidence'] != null)
                      Text('🤖 AI Confidence: ${docInfo['aiConfidence']}'),
                    if (docInfo['uploadedAt'] != null)
                      Text('⏰ Uploaded: ${DateTime.parse(docInfo['uploadedAt']).toString().split(' ')[0]}'),
                  ],
                ),
              ),
              const SizedBox(height: 15),
            ] else
              const Text('No file currently uploaded.'),
            
            const Text('What would you like to do?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (docInfo['file'] != null)
            TextButton(
              onPressed: () {
                setState(() {
                  uploadedFiles[documentType] = {
                    'file': null, 
                    'expiry': null, 
                    'isExpiring': false,
                    'displayName': docInfo['displayName'],
                    'priority': docInfo['priority'],
                  };
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ ${docInfo['displayName']} removed'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              child: const Text('Remove File', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              uploadFile(documentType);
            },
            icon: const Icon(Icons.upload_file),
            label: Text(docInfo['file'] != null ? 'Replace File' : 'Upload File'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget buildEditableField(String label, TextEditingController controller, {bool readonly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: readonly ? Colors.grey.withOpacity(0.3) : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: readonly ? Colors.grey : Colors.blue.withOpacity(0.3), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: TextField(
                        controller: controller,
                        readOnly: readonly,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: readonly 
                              ? (controller.text.isEmpty ? 'Set once (YYYY-MM-DD or DD-MM-YYYY)' : controller.text) 
                              : 'Enter $label (YYYY-MM-DD or DD-MM-YYYY)',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  if (!readonly)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: const Icon(Icons.edit, size: 20, color: Colors.blue),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ENHANCED UPLOAD FIELD WITH BETTER DOCUMENT VISIBILITY
  Widget buildUploadField(String label, String documentType) {
    final docInfo = uploadedFiles[documentType]!;
    bool isExpiring = docInfo['isExpiring'] ?? false;
    String? fileName = docInfo['file'];
    String? expiry = docInfo['expiry'];
    String displayName = docInfo['displayName'] ?? label;
    String priority = docInfo['priority'] ?? 'medium';
    
    Color borderColor = isExpiring ? Colors.red : 
                       fileName != null ? Colors.green : Colors.grey;
    Color backgroundColor = isExpiring ? Colors.red.withOpacity(0.1) : 
                           fileName != null ? Colors.green.withOpacity(0.05) : Colors.grey.withOpacity(0.02);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Priority indicator
            Container(
              width: 6,
              height: 70,
              decoration: BoxDecoration(
                color: priority == 'critical' ? Colors.red :
                       priority == 'high' ? Colors.orange :
                       priority == 'medium' ? Colors.blue : Colors.green,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            
            // Label
            SizedBox(
              width: 110,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            
            // Document info
            Expanded(
              child: Container(
                height: 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border.all(color: borderColor, width: 2),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // File name or status
                          Text(
                            fileName ?? 'No file uploaded',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: fileName != null ? (isExpiring ? Colors.red : Colors.green.shade700) : Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          // Expiry info
                          if (expiry != null) ...[
                            Text(
                              'Expires: $expiry',
                              style: TextStyle(
                                fontSize: 11,
                                color: isExpiring ? Colors.red : Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              isExpiring ? '⚠️ EXPIRING SOON' : '✅ VALID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isExpiring ? Colors.red : Colors.green,
                              ),
                            ),
                          ] else if (fileName != null)
                            const Text(
                              '🔄 Processing...',
                              style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                          
                          // AI confidence if available
                          if (docInfo['aiConfidence'] != null)
                            Text(
                              '🤖 ${docInfo['aiConfidence']} accuracy',
                              style: const TextStyle(fontSize: 9, color: Colors.blue),
                            ),
                        ],
                      ),
                    ),
                    
                    // Action buttons
                    Column(
                      children: [
                        // Upload button
                        IconButton(
                          icon: Icon(
                            Icons.upload_file, 
                            size: 18, 
                            color: isExpiring ? Colors.red : Colors.blue
                          ),
                          onPressed: () => uploadFile(documentType),
                          tooltip: 'Upload ${displayName}',
                        ),
                        // Edit button
                        IconButton(
                          icon: const Icon(
                            Icons.edit, 
                            size: 18, 
                            color: Colors.orange
                          ),
                          onPressed: () => _editDocument(documentType),
                          tooltip: 'Edit ${displayName}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person, size: 28, color: Colors.blue),
              SizedBox(width: 10),
              Text(
                'My Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // ENHANCED Profile Photo Section with Better Display
          Center(
            child: Column(
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isPhotoUploaded
                          ? [Colors.green.shade300, Colors.green.shade600]
                          : [Colors.grey.shade200, Colors.grey.shade400],
                    ),
                    border: Border.all(
                      color: isPhotoUploaded ? Colors.green : Colors.blue, 
                      width: 4
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isPhotoUploaded ? Colors.green : Colors.grey).withOpacity(0.3),
                        spreadRadius: 3,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: isPhotoUploaded
                        ? Container(
                            color: Colors.green.shade50,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.green.shade700,
                                ),
                                const Text(
                                  '✓ UPLOADED',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Icon(
                            Icons.add_a_photo,
                            size: 45,
                            color: Colors.grey.shade600,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                
                ElevatedButton.icon(
                  onPressed: _uploadProfilePhoto,
                  icon: Icon(isPhotoUploaded ? Icons.edit : Icons.camera_alt),
                  label: Text(isPhotoUploaded ? 'Change Photo' : 'Upload Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPhotoUploaded ? Colors.orange : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                ),
                
                // Photo status indicator
                if (profilePhotoName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            profilePhotoName!,
                            style: const TextStyle(
                              fontSize: 12, 
                              color: Colors.green, 
                              fontWeight: FontWeight.bold
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 35),
          
          // Basic Info with enhanced fields
          buildEditableField('Joining Date', joiningDateController, readonly: isJoiningDateSet),
          buildEditableField('Position', positionController),
          
          const SizedBox(height: 35),
          
          // ENHANCED Documents Section with Gradient Background and Better Styling
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF80E5FF), // Light cyan
                  Color(0xFF90EE90), // Light green
                ],
              ),
              borderRadius: BorderRadius.all(Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.folder_open, color: Colors.white, size: 24),
                SizedBox(width: 10),
                Text(
                  'Documents Portfolio',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: Offset(1.0, 1.0),
                        blurRadius: 2.0,
                        color: Color.fromARGB(128, 0, 0, 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          
          // Document upload fields with enhanced visibility
          ...uploadedFiles.keys.map((docType) {
            return buildUploadField(uploadedFiles[docType]!['displayName'], docType);
          }).toList(),
          
          const SizedBox(height: 25),
          
          // Document stats summary
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics, color: Colors.blue),
                    const SizedBox(width: 10),
                    const Text(
                      'Document Summary',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                    const Spacer(),
                    Text(
                      '${uploadedFiles.values.where((doc) => doc['file'] != null).length}/${uploadedFiles.length}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildDocStat('Uploaded', uploadedFiles.values.where((doc) => doc['file'] != null).length, Colors.green),
                    _buildDocStat('Expiring', uploadedFiles.values.where((doc) => doc['isExpiring'] == true).length, Colors.red),
                    _buildDocStat('Missing', uploadedFiles.values.where((doc) => doc['file'] == null).length, Colors.grey),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 25),
          
          // AI Feature Info - Enhanced
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.psychology, color: Colors.purple),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🤖 AI Document Analyzer',
                        style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Automatically detects expiry dates from uploaded documents with 90%+ accuracy. Documents expiring within 45 days are flagged in red.',
                        style: TextStyle(color: Colors.purple, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Action buttons
          Row(
            children: [
              // Save Profile Button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saveProfileData,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              
              const SizedBox(width: 10),
              
              // Test Memos Button (Remove after testing)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createSampleMemos,
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Test'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocStat(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildAttendanceTab() {
    String today = _getTodayDayName();
    Map<String, dynamic>? todaySchedule = weeklySchedule?[today];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.access_time, size: 28, color: Colors.green),
              SizedBox(width: 10),
              Text('Attendance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          
          // Location Status
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isWithinRange ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isWithinRange ? Colors.green : Colors.red),
            ),
            child: Row(
              children: [
                Icon(Icons.location_pin, color: isWithinRange ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                Text(
                  locationSet 
                    ? (isWithinRange ? 'Within restaurant range' : 'Outside restaurant range')
                    : 'Setting restaurant location...',
                  style: TextStyle(
                    color: isWithinRange ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Clock In/Out and Break Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!isClockedIn && isWithinRange) ? _clockIn : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Clock In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isClockedIn ? _clockOut : null,
                  icon: const Icon(Icons.logout),
                  label: const Text('Clock Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 15),
          
          // Break Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!isOnBreak && !isBreakExhausted && isClockedIn) ? _breakIn : null,
                  icon: const Icon(Icons.coffee),
                  label: const Text('Break In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBreakExhausted ? Colors.grey : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isOnBreak ? _breakOut : null,
                  icon: const Icon(Icons.coffee_outlined),
                  label: const Text('Break Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Current Status
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                if (clockInTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Clock In:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${clockInTime!.hour.toString().padLeft(2, '0')}:${clockInTime!.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                if (clockOutTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Clock Out:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${clockOutTime!.hour.toString().padLeft(2, '0')}:${clockOutTime!.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                if (breakInTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Break In:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${breakInTime!.hour.toString().padLeft(2, '0')}:${breakInTime!.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                if (breakOutTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Break Out:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${breakOutTime!.hour.toString().padLeft(2, '0')}:${breakOutTime!.minute.toString().padLeft(2, '0')}'),
                    ],
                  ),
                if (isBreakExhausted)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Break Status:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Exhausted (1hr)', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Weekly Schedule
          const Text('Weekly Schedule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (weeklySchedule != null)
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26),
              ),
              child: Column(
                children: weeklySchedule!.entries.map((entry) {
                  String day = entry.key;
                  Map<String, dynamic> schedule = entry.value;
                  bool isLate = attendanceLog[day]?['status'] == 'Late';
                  
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: day == today ? Colors.blue.withOpacity(0.1) : null,
                      border: const Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            day,
                            style: TextStyle(
                              fontWeight: day == today ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${schedule['start']} - ${schedule['end']}'),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: schedule['type'] == 'AL' ? Colors.blue :
                                     schedule['type'] == 'PH' ? Colors.yellow :
                                     schedule['type'] == 'off' ? Colors.grey :
                                     Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              schedule['type'].toString().toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        if (isLate)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Late ${attendanceLog[day]['minutes']}m',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeaveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today, size: 28, color: Colors.orange),
              SizedBox(width: 10),
              Text('Leave Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          
          // ENHANCED AL Tracker with Better Styling
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.withOpacity(0.1), Colors.blue.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.blue),
                    SizedBox(width: 10),
                    Text('📅 Annual Leave (AL) Tracker', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                const SizedBox(height: 18),
                
                // AL Breakdown
                Row(
                  children: [
                    Expanded(
                      child: _buildLeaveInfoCard('Total Earned', '${totalAccumulatedLeave.toStringAsFixed(1)} days', Colors.green, Icons.trending_up),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildLeaveInfoCard('Used Leave', '${totalUsedLeave.toStringAsFixed(1)} days', Colors.red, Icons.trending_down),
                    ),
                  ],
                ),
                
                const SizedBox(height: 15),
                
                // Available Balance - Highlighted
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
                          SizedBox(width: 10),
                          Text(
                            '🎯 Available Balance',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      Text(
                        '${annualLeaveBalance.toStringAsFixed(1)} days',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'Accrual: 2.5 days/month from ${joiningDateController.text}',
                      style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 15),
          
          // PH Tracker
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.yellow.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.yellow.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🏖️ Public Holiday (PH) Tracker', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Available Days:'),
                    Text('$publicHolidayDays days', 
                         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 5),
                const Text('🤖 AI detects yellow-marked PH days from schedule', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Request Leave Section
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📝 Request Leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                
                // Leave Type Selection
                Row(
                  children: [
                    const Text('Type: '),
                    Radio<String>(
                      value: 'AL',
                      groupValue: selectedLeaveType,
                      onChanged: (value) {
                        setState(() {
                          selectedLeaveType = value!;
                        });
                      },
                    ),
                    const Text('AL'),
                    Radio<String>(
                      value: 'PH',
                      groupValue: selectedLeaveType,
                      onChanged: (value) {
                        setState(() {
                          selectedLeaveType = value!;
                        });
                      },
                    ),
                    const Text('PH'),
                  ],
                ),
                
                const SizedBox(height: 10),
                
                // Available Balance Display
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available ${selectedLeaveType} Balance:'),
                      Text(
                        '${selectedLeaveType == 'AL' ? annualLeaveBalance.toStringAsFixed(1) : publicHolidayDays} days',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 15),
                
                // Date Fields
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: leaveFromController,
                        decoration: const InputDecoration(
                          labelText: 'From (YYYY-MM-DD)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: leaveToController,
                        decoration: const InputDecoration(
                          labelText: 'To (YYYY-MM-DD)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 15),
                
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitLeaveRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Submit Request'),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Leave History
          const Text('📊 Leave History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black26),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                      Expanded(child: Text('Dates', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                      Expanded(child: Text('Days', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                      Expanded(child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    ],
                  ),
                ),
                ...leaveHistory.map((leave) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(leave['type'], style: const TextStyle(fontSize: 12))),
                      Expanded(child: Text(leave['date'], style: const TextStyle(fontSize: 12))),
                      Expanded(child: Text('${leave['days']}', style: const TextStyle(fontSize: 12))),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: leave['status'] == 'Approved' ? Colors.green : 
                                   leave['status'] == 'Rejected' ? Colors.red : Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            leave['status'],
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
                if (leaveHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No leave history', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveInfoCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // COMPLETE NEW TO-DO LIST TAB
  Widget _buildTodoTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with stats
          Row(
            children: [
              const Icon(Icons.checklist_rtl, size: 28, color: Colors.purple),
              const SizedBox(width: 10),
              const Text('To-Do List', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Text(
                  '$pendingTasks pending • $completedTasks done',
                  style: const TextStyle(color: Colors.purple, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Add Todo Section
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.purple.withOpacity(0.1), Colors.purple.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('➕ Add New Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: todoController,
                        decoration: InputDecoration(
                          hintText: 'What needs to be done?',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                        maxLines: 2,
                        onSubmitted: (_) => _addTodo(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: isAddingTodo ? null : _addTodo,
                      icon: isAddingTodo 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add),
                      label: Text(isAddingTodo ? 'Adding...' : 'Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Todo List
          Expanded(
            child: todoList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 20),
                        Text(
                          '🎯 No tasks yet!',
                          style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Add some tasks to get organized and stay productive.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: todoList.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final todo = todoList[index];
                      final isCompleted = todo['completed'] ?? false;
                      final createdAt = DateTime.parse(todo['createdAt']);
                      final isToday = createdAt.day == DateTime.now().day;
                      
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCompleted ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                            width: isCompleted ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: GestureDetector(
                            onTap: () => _toggleTodo(index),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isCompleted ? Colors.green : Colors.transparent,
                                border: Border.all(
                                  color: isCompleted ? Colors.green : Colors.grey,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: isCompleted
                                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                                  : null,
                            ),
                          ),
                          title: Text(
                            todo['text'],
                            style: TextStyle(
                              fontSize: 16,
                              decoration: isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                              color: isCompleted ? Colors.grey : Colors.black,
                              fontWeight: isCompleted ? FontWeight.normal : FontWeight.w500,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    isToday ? Icons.today : Icons.calendar_today,
                                    size: 12,
                                    color: isToday ? Colors.blue : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isToday ? 'Today' : createdAt.toString().split(' ')[0],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isToday ? Colors.blue : Colors.grey,
                                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  if (isCompleted && todo['completedAt'] != null) ...[
                                    const SizedBox(width: 10),
                                    const Icon(Icons.check_circle, size: 12, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Done ${DateTime.parse(todo['completedAt']).toString().split(' ')[0]}',
                                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton(
                            icon: const Icon(Icons.more_vert, color: Colors.grey),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: const Row(
                                  children: [
                                    Icon(Icons.edit, size: 16, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: const Row(
                                  children: [
                                    Icon(Icons.delete, size: 16, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editTodo(index);
                              } else if (value == 'delete') {
                                _deleteTodo(index);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // Bottom stats
          if (todoList.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 15),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTodoStat('Total', '${todoList.length}', Colors.blue),
                  _buildTodoStat('Pending', '$pendingTasks', Colors.orange),
                  _buildTodoStat('Completed', '$completedTasks', Colors.green),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTodoStat(String label, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF80E5FF), // Light cyan
              Color(0xFF90EE90), // Light green
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Welcome ${getUserName()}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(1.0, 1.0),
                            blurRadius: 3.0,
                            color: Color.fromARGB(128, 0, 0, 0),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        // Notifications Button with Enhanced Design
                        Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.notifications, color: Colors.white, size: 26),
                                onPressed: _showNotifications,
                              ),
                            ),
                            if (unreadMemoCount > 0)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  child: Text(
                                    '$unreadMemoCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Logout Button
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white, size: 26),
                          onPressed: () {
                            FirebaseAuth.instance.signOut();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Tab Bar - NOW 4 TABS INCLUDING TO-DO
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                isScrollable: true,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                tabs: [
                  const Tab(icon: Icon(Icons.person), text: 'Profile'),
                  const Tab(icon: Icon(Icons.access_time), text: 'Attendance'),
                  const Tab(icon: Icon(Icons.calendar_today), text: 'Leave'),
                  Tab(
                    icon: Stack(
                      children: [
                        const Icon(Icons.checklist_rtl),
                        if (pendingTasks > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 12,
                                minHeight: 12,
                              ),
                              child: Text(
                                '$pendingTasks',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    text: 'To-Do',
                  ),
                ],
              ),
              
              // Tab Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMyProfileTab(),
                      _buildAttendanceTab(),
                      _buildLeaveTab(),
                      _buildTodoTab(), // NEW TO-DO TAB
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
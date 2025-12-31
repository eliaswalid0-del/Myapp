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
  
  // Document uploads with expiry tracking
  Map<String, Map<String, dynamic>> uploadedFiles = {
    'passport': {'file': null, 'expiry': null, 'isExpiring': false},
    'eid': {'file': null, 'expiry': null, 'isExpiring': false},
    'workVisa': {'file': null, 'expiry': null, 'isExpiring': false},
    'labourCard': {'file': null, 'expiry': null, 'isExpiring': false},
    'bfhtCertificate': {'file': null, 'expiry': null, 'isExpiring': false},
    'picCertificate': {'file': null, 'expiry': null, 'isExpiring': false},
    'ohc': {'file': null, 'expiry': null, 'isExpiring': false},
  };

  // Schedule data
  Map<String, dynamic>? weeklySchedule;
  Map<String, dynamic> attendanceLog = {}; // Track late arrivals

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
    _loadMemos();
    _checkLocationPermission();
    _loadScheduleData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    joiningDateController.dispose();
    positionController.dispose();
    leaveFromController.dispose();
    leaveToController.dispose();
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
        'content': 'Please update your profile and upload all required documents by end of week.',
        'from': 'Manager',
        'timestamp': FieldValue.serverTimestamp(),
        'targetAudience': 'employees',
        'readBy': [],
      });

      // Sample memo 2  
      await FirebaseFirestore.instance.collection('memos').add({
        'title': 'New Break Policy',
        'content': 'Reminder: Break time is limited to 1 hour per day. Please clock out properly.',
        'from': 'Ops Manager',
        'timestamp': FieldValue.serverTimestamp(),
        'targetAudience': 'all',
        'readBy': [],
      });

      // Sample memo 3
      await FirebaseFirestore.instance.collection('memos').add({
        'title': 'Document Expiry Alert',
        'content': 'Several employees have documents expiring soon. Please check your profile and renew them.',
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
        title: const Text('Notifications'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: memos.length,
            itemBuilder: (context, index) {
              final memo = memos[index];
              return Card(
                color: memo['isRead'] ? Colors.grey.shade100 : Colors.blue.shade50,
                child: ListTile(
                  title: Text(
                    memo['title'],
                    style: TextStyle(
                      fontWeight: memo['isRead'] ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text('From: ${memo['from']}\nDate: ${memo['timestamp']}'),
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
        title: Text(memo['title']),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('From: ${memo['from']}'),
              Text('Date: ${memo['timestamp']}'),
              const SizedBox(height: 10),
              Text(memo['content']),
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

  Future<void> _uploadProfilePhoto() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          profilePhotoName = result.files.single.name;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile photo ${result.files.single.name} uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo upload failed: $e'),
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
            isJoiningDateSet = data['joiningDate'] != null && data['joiningDate'].isNotEmpty;
            restaurantLat = data['restaurantLat'];
            restaurantLng = data['restaurantLng'];
            locationSet = restaurantLat != null && restaurantLng != null;
            
            // Load uploaded files
            if (data['documents'] != null) {
              Map<String, dynamic> docs = Map<String, dynamic>.from(data['documents']);
              docs.forEach((key, value) {
                if (uploadedFiles.containsKey(key)) {
                  uploadedFiles[key] = Map<String, dynamic>.from(value);
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
            content: Text('Profile saved successfully!'),
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
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _calculateLeaveBalance() async {
    if (joiningDateController.text.isNotEmpty) {
      try {
        DateTime joiningDate = DateTime.parse(joiningDateController.text);
        DateTime now = DateTime.now();
        
        // Calculate complete months from joining date to today
        int monthsWorked = (now.year - joiningDate.year) * 12 + now.month - joiningDate.month;
        
        // If current day is before joining day in the month, subtract 1 month
        if (now.day < joiningDate.day) {
          monthsWorked--;
        }
        
        // Ensure non-negative months
        monthsWorked = monthsWorked < 0 ? 0 : monthsWorked;
        
        // Calculate total accumulated leave (2.5 days per month)
        double totalAccumulated = monthsWorked * 2.5;
        
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
        
        print('Months worked: $monthsWorked, Total accumulated: $totalAccumulated, Used: $usedLeaveDays, Available: $annualLeaveBalance');
      } catch (e) {
        print('Error calculating leave balance: $e');
      }
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

  Future<void> uploadFile(String documentType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          uploadedFiles[documentType]!['file'] = result.files.single.name;
        });
        
        await _analyzeDocumentExpiry(result.files.single.name!, documentType);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.single.name} uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _analyzeDocumentExpiry(String fileName, String docType) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate AI processing
    
    // Mock AI analysis - in real app, use OCR/AI service
    DateTime mockExpiryDate = DateTime.now().add(const Duration(days: 30)); // Mock 30 days
    
    setState(() {
      uploadedFiles[docType]!['expiry'] = mockExpiryDate.toString().split(' ')[0];
      uploadedFiles[docType]!['isExpiring'] = mockExpiryDate.difference(DateTime.now()).inDays <= 45;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('AI Analysis: $docType expires on ${mockExpiryDate.toString().split(' ')[0]}'),
        backgroundColor: uploadedFiles[docType]!['isExpiring'] ? Colors.red : Colors.blue,
        duration: const Duration(seconds: 3),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${documentType.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current file: ${uploadedFiles[documentType]!['file'] ?? 'None'}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                uploadFile(documentType);
              },
              child: const Text('Replace File'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  uploadedFiles[documentType] = {'file': null, 'expiry': null, 'isExpiring': false};
                });
                Navigator.pop(context);
              },
              child: const Text('Remove File', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
              height: 40,
              decoration: BoxDecoration(
                color: readonly ? Colors.grey.withOpacity(0.3) : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: controller,
                        readOnly: readonly,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: readonly ? (controller.text.isEmpty ? 'Set once' : controller.text) : 'Enter $label (YYYY-MM-DD)',
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  if (!readonly)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18, color: Colors.black54),
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildUploadField(String label, String documentType) {
    bool isExpiring = uploadedFiles[documentType]!['isExpiring'] ?? false;
    String? fileName = uploadedFiles[documentType]!['file'];
    String? expiry = uploadedFiles[documentType]!['expiry'];

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
              height: 50,
              decoration: BoxDecoration(
                color: isExpiring ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isExpiring ? Colors.red : Colors.black26),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            fileName ?? 'No file uploaded',
                            style: TextStyle(
                              fontSize: 12,
                              color: fileName != null ? (isExpiring ? Colors.red : Colors.green) : Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (expiry != null)
                            Text(
                              'Expires: $expiry',
                              style: TextStyle(
                                fontSize: 10,
                                color: isExpiring ? Colors.red : Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Upload button
                  IconButton(
                    icon: Icon(
                      Icons.upload_file, 
                      size: 18, 
                      color: isExpiring ? Colors.red : Colors.blue
                    ),
                    onPressed: () => uploadFile(documentType),
                  ),
                  // Edit button
                  IconButton(
                    icon: const Icon(
                      Icons.edit, 
                      size: 18, 
                      color: Colors.orange
                    ),
                    onPressed: () => _editDocument(documentType),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          
          // Profile Photo Section
          Center(
            child: Column(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade200,
                    border: Border.all(color: Colors.blue, width: 2),
                  ),
                  child: profilePhotoName != null
                      ? ClipOval(
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey.shade600,
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.grey.shade600,
                        ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _uploadProfilePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(profilePhotoName != null ? 'Change Photo' : 'Upload Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (profilePhotoName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      profilePhotoName!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Basic Info
          buildEditableField('Joining Date', joiningDateController, readonly: isJoiningDateSet),
          buildEditableField('Position', positionController),
          
          const SizedBox(height: 30),
          
          // Documents Section with Gradient Background
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF80E5FF), // Light cyan
                  Color(0xFF90EE90), // Light green
                ],
              ),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: const Text(
              'Documents',
              style: TextStyle(
                fontSize: 18,
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
          ),
          const SizedBox(height: 15),
          
          ...uploadedFiles.keys.map((docType) {
            String displayName = docType == 'eid' ? 'EID' :
                               docType == 'workVisa' ? 'Work Visa' :
                               docType == 'labourCard' ? 'Labour Card' :
                               docType == 'bfhtCertificate' ? 'BFHT Certificate' :
                               docType == 'picCertificate' ? 'PIC Certificate' :
                               docType == 'ohc' ? 'OHC' :
                               docType.toUpperCase();
            return buildUploadField(displayName, docType);
          }).toList(),
          
          const SizedBox(height: 30),
          
          // AI Feature Info
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.smart_toy, color: Colors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI Expiry Reader: Documents expiring within 45 days are marked in red',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveProfileData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Save Profile',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          
          const SizedBox(height: 15),
          
          // Test Memos Button (Remove after testing)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _createSampleMemos,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Create Test Memos (Remove Later)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
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
          
          // AL Tracker
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Annual Leave (AL) Tracker', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Accumulated:'),
                    Text('${totalAccumulatedLeave.toStringAsFixed(1)} days', 
                         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Used Leave:'),
                    Text('${totalUsedLeave.toStringAsFixed(1)} days', 
                         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Available Balance:'),
                    Text('${annualLeaveBalance.toStringAsFixed(1)} days', 
                         style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                const SizedBox(height: 5),
                const Text('Accrual: 2.5 days/month from joining date', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                const Text('Public Holiday (PH) Tracker', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                const Text('AI detects yellow-marked PH days from schedule', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                const Text('Request Leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
          const Text('Leave History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        // Notifications Button
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications, color: Colors.white),
                              onPressed: _showNotifications,
                            ),
                            if (unreadMemoCount > 0)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    '$unreadMemoCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Logout Button
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white),
                          onPressed: () {
                            FirebaseAuth.instance.signOut();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Tab Bar
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(icon: Icon(Icons.person), text: 'Profile'),
                  Tab(icon: Icon(Icons.access_time), text: 'Attendance'),
                  Tab(icon: Icon(Icons.calendar_today), text: 'Leave'),
                ],
              ),
              
              // Tab Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMyProfileTab(),
                      _buildAttendanceTab(),
                      _buildLeaveTab(),
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
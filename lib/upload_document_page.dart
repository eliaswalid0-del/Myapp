import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class UploadDocumentPage extends StatefulWidget {
  final String documentType;

  const UploadDocumentPage({super.key, required this.documentType});

  @override
  State<UploadDocumentPage> createState() => _UploadDocumentPageState();
}

class _UploadDocumentPageState extends State<UploadDocumentPage> {
  PlatformFile? selectedFile;
  bool isUploading = false;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true, // REQUIRED for Web
    );

    if (result != null) {
      setState(() {
        selectedFile = result.files.single;
      });
    }
  }

  Future<void> uploadDocument() async {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please choose a file first.")),
      );
      return;
    }

    setState(() => isUploading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final ext = selectedFile!.extension ?? "file";
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("documents/$uid/${widget.documentType}.$ext");

      // -------------------------
      // 1. Upload (Web + Mobile using bytes only)
      // -------------------------
      if (selectedFile!.bytes == null) {
        throw Exception("File data missing. Please re-select the file.");
      }

      await storageRef.putData(
        selectedFile!.bytes!,
        SettableMetadata(
          contentType: "application/octet-stream",
        ),
      );

      final downloadUrl = await storageRef.getDownloadURL();

      // -------------------------
      // 2. Call Cloud Function
      // -------------------------
      final response = await http.post(
        Uri.parse(
          "https://us-central1-studio-6313173084-d2ab9.cloudfunctions.net/runExpiryCheckNow",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fileUrl": downloadUrl,
          "documentType": widget.documentType,
        }),
      );

      final result = jsonDecode(response.body);
      final expiryDate = result["expiryDate"];
      final status = result["status"]; // green or red

      // -------------------------
      // 3. Save to Firestore
      // -------------------------
      await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .collection("documents")
          .doc(widget.documentType)
          .set({
        "url": downloadUrl,
        "expiryDate": expiryDate,
        "status": status,
        "uploadedAt": DateTime.now().toIso8601String(),
      });

      // -------------------------
      // 4. Done
      // -------------------------
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Document uploaded successfully.")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Upload ${widget.documentType.toUpperCase()}"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            OutlinedButton(
              onPressed: pickFile,
              child: const Text("Choose File"),
            ),

            const SizedBox(height: 20),

            if (selectedFile != null)
              Text(
                "Selected: ${selectedFile!.name}",
                style: const TextStyle(fontSize: 16),
              ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isUploading ? null : uploadDocument,
                child: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Upload"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

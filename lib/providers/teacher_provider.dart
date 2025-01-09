import 'package:flutter/material.dart';

// Dummy Provider (replace with actual API call)
class TeacherProvider with ChangeNotifier {
  String teacherName = "Zain Ali";
  String avatarUrl = "https://firebasestorage.googleapis.com/v0/b/unisoft-tmp.appspot.com/o/Default%2Fdummy-profile.png?alt=media&token=ebbb29f7-0ab8-4437-b6d5-6b2e4cfeaaf7";
bool hasMeetingRoom= true;
  void fetchTeacherData() {
    // Replace with actual API call logic
    teacherName = "Teacher Demo";
    avatarUrl = "https://institute.zbmtech.com";
    notifyListeners();
  }
}
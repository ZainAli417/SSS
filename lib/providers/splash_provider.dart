import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:videosdk_flutter_example/screens/TeacherScreen.dart';
import '../screens/Navbar.dart';

class SplashProvider with ChangeNotifier {
 // final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> navigateToNextScreen(BuildContext context) async {
    await Future.delayed(Duration(seconds: 3));

    //User? currentUser = _auth.currentUser;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => TeacherScreen()),
      );
    /*

    if (currentUser != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => navbar()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    }

     */
  }
}

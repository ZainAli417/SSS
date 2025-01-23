import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:videosdk/videosdk.dart';
import 'package:videosdk_flutter_example/constants/colors.dart';
import 'package:videosdk_flutter_example/screens/SplashScreen.dart';
import 'package:videosdk_flutter_example/screens/common/join_screen.dart';
import 'package:videosdk_flutter_example/utils/api.dart';
import 'package:videosdk_flutter_example/utils/spacer.dart';
import 'package:videosdk_flutter_example/utils/toast.dart';
import 'package:videosdk_flutter_example/widgets/common/app_bar/recording_indicator.dart';

import '../../../providers/role_provider.dart';
import '../../../providers/teacher_provider.dart';
import '../../../screens/TeacherScreen.dart';

class MeetingAppBar extends StatefulWidget {
  final String token;
  final Room meeting;
  final String recordingState;
  final bool isFullScreen;
  const MeetingAppBar(
      {Key? key,
      required this.meeting,
      required this.token,
      required this.isFullScreen,
      required this.recordingState})
      : super(key: key);

  @override
  State<MeetingAppBar> createState() => MeetingAppBarState();
}

class MeetingAppBarState extends State<MeetingAppBar> {
  Duration? elapsedTime;
  Timer? sessionTimer;

  String? selectedTeacher;
  List<String> teacherList = [];

  List<VideoDeviceInfo>? cameras = [];

  @override
  void initState() {
    startTimer();
    fetchCameras();
    super.initState();
    fetchTeachers();
  }

  void fetchCameras() async {
    cameras = await VideoSDK.getVideoDevices();
  }

  void fetchTeachers() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('room_metadata')
          .doc('i5NpyLzF5fE1zKyPa9r1') // Correct document path
          .get();

      if (snapshot.exists) {
        var data = snapshot.data();
        if (data != null && data.containsKey('teacher_list')) {
          // teacher_list is a field
          List<dynamic> fetchedTeachers = data['teacher_list'];
          setState(() {
            teacherList = List<String>.from(fetchedTeachers);
          });
        }
      }
    } catch (e) {
      print('Error fetching teachers: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 300),
      crossFadeState: !widget.isFullScreen
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      secondChild: const SizedBox.shrink(),
      firstChild: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 10.0, 8.0, 0.0),
        child: Row(
          children: [
            // Go Back Arrow
            IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white,
              ),
              onPressed: () {
                // Get the RoleProvider instance
                final roleProvider = Provider.of<RoleProvider>(context, listen: false);

                // Pop the current screen and call meeting.leave() method
                Navigator.pop(context);
                widget.meeting.leave(); // Call meeting.leave() method

                // Check the role and navigate to the appropriate screen
                if (roleProvider.isPrincipal) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => TeacherScreen()), // Navigate to TeacherScreen
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => SplashScreen()), // Navigate to SplashScreen
                  );
                }
              },
            ),

            if (widget.recordingState == "RECORDING_STARTING" ||
                widget.recordingState == "RECORDING_STOPPING" ||
                widget.recordingState == "RECORDING_STARTED")
              RecordingIndicator(recordingState: widget.recordingState),
            if (widget.recordingState == "RECORDING_STARTING" ||
                widget.recordingState == "RECORDING_STOPPING" ||
                widget.recordingState == "RECORDING_STARTED")
              const HorizontalSpacer(),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.meeting.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        child: const Padding(
                          padding: EdgeInsets.fromLTRB(8, 0, 0, 0),
                          child: Icon(
                            Icons.copy,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.meeting.id));
                          showSnackBarMessage(
                              message: "Meeting ID has been copied.",
                              context: context);
                        },
                      ),
                    ],
                  ),
                  /*Text(
                    elapsedTime == null
                        ? "00:00:00"
                        : elapsedTime.toString().split(".").first,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey),
                  )*/
                ],
              ),
            ),
            Consumer<RoleProvider>(
              builder: (context, roleProvider, child) {
                if (roleProvider.isPrincipal) {
                  return Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedTeacher,
                          hint:  Text(
                            "Assign Meeting",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                          ),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: Colors.white),
                          dropdownColor: Colors.black87,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: Colors.white70),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          items: teacherList.map((String teacher) {
                            return DropdownMenuItem<String>(
                              value: teacher,
                              child: Text(teacher),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              selectedTeacher = newValue;
                            });
                            if (newValue != null) {
                              savedata(newValue);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                } else {
                  // Return an empty container if the conditions are not met
                  return SizedBox.shrink();
                }
              },
            ),
            IconButton(
              icon: SvgPicture.asset(
                "assets/ic_switch_camera.svg",
                height: 24,
                width: 24,
              ),
              onPressed: () {
                VideoDeviceInfo? newCam = cameras?.firstWhere((camera) =>
                    camera.deviceId != widget.meeting.selectedCam?.deviceId);
                if (newCam != null) {
                  widget.meeting.changeCam(newCam);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void savedata(String teacher) async {
    try {
      // Add a new document with auto-generated ID
      await FirebaseFirestore.instance.collection('meeting_record').add({
        'assigned_to': teacher,
        'room_id': widget.meeting.id,
        'room_name': 'Zain Ali',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Meeting assigned to $selectedTeacher')),
      );
    } catch (e) {
      print('Error assigning meeting: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to assign meeting')),
      );
    }
  }

  Future<void> startTimer() async {
    dynamic session = await fetchSession(widget.token, widget.meeting.id);
    DateTime sessionStartTime = DateTime.parse(session['start']);
    final difference = DateTime.now().difference(sessionStartTime);

    setState(() {
      elapsedTime = difference;
      sessionTimer = Timer.periodic(
        const Duration(seconds: 1),
        (timer) {
          setState(() {
            elapsedTime = Duration(
                seconds: elapsedTime != null ? elapsedTime!.inSeconds + 1 : 0);
          });
        },
      );
    });
    // log("session start time" + session.data[0].start.toString());
  }

  @override
  void dispose() {
    if (sessionTimer != null) {
      sessionTimer!.cancel();
    }
    super.dispose();
  }
}

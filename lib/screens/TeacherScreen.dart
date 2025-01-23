import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_echarts/flutter_echarts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:videosdk_flutter_example/screens/SplashScreen.dart';
import 'package:videosdk_flutter_example/screens/conference-call/conference_meeting_screen.dart';
import '../providers/teacher_provider.dart';
import 'common/join_screen.dart';

class TeacherScreen extends StatefulWidget {
  @override
  _TeacherScreenState createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  bool isRejoin = false;
  get token => 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcGlrZXkiOiJhNmQ5OTI3NC1hMTIyLTRiYzMtYmJhOS0wNDYyOTcyNWNiMDQiLCJwZXJtaXNzaW9ucyI6WyJhbGxvd19qb2luIl0sImlhdCI6MTczNjIyMzYzNywiZXhwIjoxODk0MDExNjM3fQ.TdZwUNK6jQ-SZjCvabdIvnnbpk2wWvSCruRSxLKEMsY';
  List<Map<String, dynamic>> statsData = [];
  Map<String, Map<String, dynamic>> participantStats = {};
  late StreamSubscription<QuerySnapshot> statsSubscription;

  @override
  void initState() {
    super.initState();
    listenToStats(); // Start listening to the Firestore collection
  }

  @override
  void dispose() {
    statsSubscription.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

// Function to listen to stats changes in Firestore
  void listenToStats() {
    statsSubscription = FirebaseFirestore.instance
        .collection('Stats')
        .snapshots()
        .listen((snapshot) {
      // Extract data into a list of maps
      // Extract data into a list of maps
      List<Map<String, dynamic>> fetchedData = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        return {
          'displayName': data['displayName'],
          'audioPlayedCount': data['audioPlayedCount'] ?? 0,
          'Q_marks': data['Q_marks'] ?? 0,
          // Check if joinTime is a Timestamp and convert to DateTime
          'joinTime': (data['joinTime'] is Timestamp)
              ? (data['joinTime'] as Timestamp).toDate()
              : DateFormat('HH:mm:ss').parse(data['joinTime']),
        };
      }).toList();



      // Update the state with the new data
      setState(() {
        statsData = fetchedData; // Update the statsData
      });
    });
  }

  Widget buildAudioAndQuizGraph() {
    return SfCartesianChart(
      primaryXAxis: CategoryAxis(),
      primaryYAxis: const NumericAxis(
        interval: 5, // Set the interval for the Y-axis
        maximum: 30,  // Adjust the maximum value as needed
      ),
      series: <CartesianSeries>[
        ColumnSeries<Map<String, dynamic>, String>(
          dataSource: statsData,
          xValueMapper: (data, _) => data['displayName'],
          yValueMapper: (data, _) => data['audioPlayedCount'],
          name: 'Audio Replay',
          color: const Color(0xFF4CAF50),
          width: 0.2, // Set column width (0.4 for narrower columns)
        ),
        ColumnSeries<Map<String, dynamic>, String>(
          dataSource: statsData,
          xValueMapper: (data, _) => data['displayName'],
          yValueMapper: (data, _) => data['Q_marks'],
          name: 'Quiz Marks(Out Of 40)',
          color: const Color(0xFFF44336),
          width: 0.2, // Set column width (0.4 for narrower columns)
        ),
      ],
      legend: const Legend(isVisible: true),
      tooltipBehavior: TooltipBehavior(enable: true),
    );
  }



  Widget buildJoinTimeGraph() {
    return SfCartesianChart(
      primaryXAxis: CategoryAxis(),
      primaryYAxis: NumericAxis(
        interval: 3600, // Set the interval for the Y-axis to 1 hour (3600 seconds)
        maximum: 86400, // Maximum value for the Y-axis set to 86400 seconds (24 hours)
        labelFormat: '{value} s', // Default label format, but will be overridden
        title: AxisTitle(text: 'Join Time'), // Optional: Add a title to the Y-axis
        axisLabelFormatter: (args) {
          int totalSeconds = args.value.toInt();
          int hours = totalSeconds ~/ 3600;
          int minutes = (totalSeconds % 3600) ~/ 60;
          int seconds = totalSeconds % 60;

          // Return ChartAxisLabel instead of String
          return ChartAxisLabel(
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            null,
          );
        },
      ),
      series: <CartesianSeries>[
        ColumnSeries<Map<String, dynamic>, String>(
          dataSource: statsData,
          xValueMapper: (data, _) => data['displayName'],
          yValueMapper: (data, _) {
            // Assuming joinTime is a DateTime object
            DateTime joinTime = data['joinTime'];

            // Convert join time to total seconds for easier Y-axis manipulation
            return (joinTime.hour * 3600) + (joinTime.minute * 60) + joinTime.second; // Total seconds
          },
          name: 'Join Time',
          color: const Color(0xFF2196F3),
          width: 0.2, // Set column width (0.2 for narrower columns)
        ),
      ],
      legend: Legend(isVisible: true),
      tooltipBehavior: TooltipBehavior(enable: true),
    );
  }


  @override
  Widget build(BuildContext context) {
    final teacherProvider = Provider.of<TeacherProvider>(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Top Section
          Stack(
            children: [
              Container(
                height: 150,
                decoration: const BoxDecoration(
                  color: Color(0xFF044B89),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
              ),
              Positioned(
                bottom: 40,
                right: 220,
                child: Container(
                  width: 300,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                        width: 1, color: Colors.white.withOpacity(0.15)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                top: 60,
                left: 30,
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 30,
                      backgroundImage: NetworkImage(teacherProvider.avatarUrl),
                    ),
                    SizedBox(width: 20),
                    Text(
                      teacherProvider.teacherName,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 50),
                    _buildLogoutButton()
                  ],
                ),
              ),
            ],
          ),
          // Body Section with Firestore Data
          const SizedBox(height: 10),
          Center(
            child: Text('Click the arrow to visit the room',
                style: GoogleFonts.poppins(fontSize: 14)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('meeting_record')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/no_data.jpg',
                        width: 400,
                        height: 500,
                      ),
                      Text(
                        'No Meetings Created Yet',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  );
                } else {
                  // Process the list of documents
                  var meetings = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: meetings.length,
                    itemBuilder: (context, index) {
                      var data = meetings[index].data() as Map<String, dynamic>;
                      var roomName = data['room_name'] ?? 'Unknown Room';
                      var roomId = data['room_id'] ?? 'N/A';
                      var assignedTo = data['assigned_to'] ?? 'Unassigned';

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 1, horizontal: 10),

                        child: SizedBox(
                          height: 400, // Define a height for the card
                          width: 500,
                          child: Card(
                            color: Colors.white,
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 5, horizontal: 10),
                                  leading: const Icon(
                                    Icons.meeting_room,
                                    color: Color(0xFF044B89),
                                    size: 40,
                                  ),
                                  title: Text(
                                    'Meeting ID: $roomId',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Assigned To: $assignedTo',
                                    style: GoogleFonts.poppins(fontSize: 14),
                                  ),
                                ),
                                const Divider(height: 1, color: Colors.grey),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => ConferenceMeetingScreen(
                                                meetingId: roomId,
                                                token: token,
                                                displayName: roomName,
                                              ),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'Rejoin',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () {
                                          FirebaseFirestore.instance
                                              .collection('meeting_record')
                                              .doc(meetings[index].id)
                                              .delete()
                                              .then((value) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Meeting deleted successfully'),
                                              ),
                                            );
                                          }).catchError((error) {
                                            print('Error deleting meeting: $error');
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Error deleting meeting'),
                                              ),
                                            );
                                          });
                                        },
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, color: Colors.grey),
                                Center(
                                  child: Text('Swipe To View more Stats->',
                                      style: GoogleFonts.poppins(fontSize: 14)),
                                ), Expanded(
                                  child: Center(

                                    child: statsData.isNotEmpty
                                        ? PageView(
                                      children: [
                                        // Audio graph
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: buildAudioAndQuizGraph(),
                                        ),
                                        // Join Time graph
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: buildJoinTimeGraph(),
                                        ),
                                      ],
                                    )
                                        : Text(
                                      "No data received yet", // Show a message if no data is available
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),


                      );
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const JoinScreen()),
          );
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: Image.asset(
            'assets/fab.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      ),
      icon: const Icon(Icons.logout_outlined, color: Colors.white),
      label: Text(
        "Logout",
        style: GoogleFonts.poppins(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SplashScreen()),
        );
      },
    );
  }
}

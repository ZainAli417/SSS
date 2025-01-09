import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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
  get token =>
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhcGlrZXkiOiJhNmQ5OTI3NC1hMTIyLTRiYzMtYmJhOS0wNDYyOTcyNWNiMDQiLCJwZXJtaXNzaW9ucyI6WyJhbGxvd19qb2luIl0sImlhdCI6MTczNjIyMzYzNywiZXhwIjoxODk0MDExNjM3fQ.TdZwUNK6jQ-SZjCvabdIvnnbpk2wWvSCruRSxLKEMsY';

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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        // Pass roomId to the RejoiningDetails screen
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  ConferenceMeetingScreen(
                                                      meetingId: roomId,
                                                      token: token,
                                                      displayName: roomName)),
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
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        // Handle delete logic
                                        FirebaseFirestore.instance
                                            .collection('meeting_record')
                                            .doc(meetings[index].id)
                                            .delete()
                                            .then((value) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Meeting deleted successfully'),
                                            ),
                                          );
                                        }).catchError((error) {
                                          print(
                                              'Error deleting meeting: $error');
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Error deleting meeting'),
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
                            ],
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
          Navigator.push(
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

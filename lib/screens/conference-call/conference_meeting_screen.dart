import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:videosdk/videosdk.dart';
import 'package:videosdk_flutter_example/constants/colors.dart';
import 'package:videosdk_flutter_example/screens/SplashScreen.dart';
import 'package:videosdk_flutter_example/screens/TeacherScreen.dart';
import 'package:videosdk_flutter_example/utils/toast.dart';
import 'package:videosdk_flutter_example/widgets/common/app_bar/meeting_appbar.dart';
import 'package:videosdk_flutter_example/widgets/common/app_bar/web_meeting_appbar.dart';
import 'package:videosdk_flutter_example/widgets/common/chat/chat_view.dart';
import 'package:videosdk_flutter_example/widgets/common/joining/waiting_to_join.dart';
import 'package:videosdk_flutter_example/widgets/common/meeting_controls/meeting_action_bar.dart';
import 'package:videosdk_flutter_example/widgets/common/participant/participant_list.dart';
import 'package:videosdk_flutter_example/widgets/conference-call/conference_participant_grid.dart';
import 'package:videosdk_flutter_example/widgets/conference-call/conference_screenshare_view.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../providers/principal_provider.dart';
import '../../providers/role_provider.dart';
import '../../providers/teacher_provider.dart';
import '../../providers/topic_provider.dart';
import '../Quiz and Audio/Audio_Player_UI.dart';

class ConferenceMeetingScreen extends StatefulWidget {
  final String meetingId, token, displayName;
  final bool micEnabled, camEnabled, chatEnabled;
  final AudioDeviceInfo? selectedAudioOutputDevice, selectedAudioInputDevice;
  final CustomTrack? cameraTrack;
  final CustomTrack? micTrack;

  const ConferenceMeetingScreen({
    Key? key,
    required this.meetingId,
    required this.token,
    required this.displayName,
    this.micEnabled = true,
    this.camEnabled = true,
    this.chatEnabled = true,
    this.selectedAudioOutputDevice,
    this.selectedAudioInputDevice,
    this.cameraTrack,
    this.micTrack,
  }) : super(key: key);

  @override
  State<ConferenceMeetingScreen> createState() =>
      _ConferenceMeetingScreenState();
}

class _ConferenceMeetingScreenState extends State<ConferenceMeetingScreen> {
  bool isRecordingOn = false;
  bool showChatSnackbar = true;
  String recordingState = "RECORDING_STOPPED";
  late Room meeting;
  bool _joined = false;
  Stream? shareStream;
  Stream? videoStream;
  Stream? audioStream;
  Stream? remoteParticipantShareStream;
  bool fullScreen = false;

  bool _isLoading = true;
  List<String> audioFiles = [];
  AudioPlayer? _currentAudioPlayer;
  String? _currentPlayingAudioUrl;
  int audioPlayedCount = 0; // Counter to track audio plays for stats
  List<Map<String, dynamic>> _broadcasts = []; // To store fetched broadcasts

  StreamSubscription? _broadcastSubscription;

  late DatabaseReference _dbRef;
  Timer? _timer;
  int _remainingMinutes = 30;
  late final bool isTeacher;
  late final bool isStudent;

  @override
  void initState() {
    isTeacher = context.read<RoleProvider>().isTeacher;
    isStudent = context.read<RoleProvider>().isStudent;
    _dbRef = FirebaseDatabase.instance.ref("remainingTime/${widget.meetingId}");

    if (isTeacher) {
      // Initialize the timer only for the principal
      _initializeTimer();
    } else {
      // Listen to the remaining time in real-time for other roles
      _listenToRemainingTime();
    }

    super.initState();
    _setupAudioFilesListener(); // Start listening for real-time updates
    _setupBroadcastListener();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Create Room instance for the meeting
    meeting = VideoSDK.createRoom(
      roomId: widget.meetingId,
      token: widget.token,
      customCameraVideoTrack: widget.cameraTrack,
      customMicrophoneAudioTrack: widget.micTrack,
      displayName: widget.displayName,
      micEnabled: widget.micEnabled,
      camEnabled: widget.camEnabled,
      maxResolution: 'hd',
      multiStream: true,
      notification: const NotificationInfo(
        title: "Video SDK",
        message: "Video SDK is sharing screen in the meeting",
        icon: "notification_share",
      ),
    );

    // Register meeting events and join
    registerMeetingEvents(meeting);
    meeting.join();
    if (isStudent) {
      // Initialize the timer only for the principal
      storeParticipantStats();
    }
  }

  void _initializeTimer() {
    _dbRef.set(_remainingMinutes); // Set initial time in the database
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        if (_remainingMinutes > 0) {
          _remainingMinutes--;
          _dbRef.set(
              _remainingMinutes); // Update the remaining time in the database
        }

        if (_remainingMinutes == 10) {
          _showWarningPopup();
        }

        if (_remainingMinutes == 0) {
          _timer?.cancel();

          meeting.end();
        }
        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    SplashScreen()), // Navigate to TeacherScreen
          );
        });
      });
    });
  }

  void _listenToRemainingTime() {
    _dbRef.onValue.listen((event) {
      final time = event.snapshot.value as int?;
      if (time != null) {
        setState(() {
          _remainingMinutes = time;
        });
      }
    });
  }
  void _showWarningPopup() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Warning'),
          content: const Text(
              'You will be automatically disconnected in 10 minutes.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
  void _setupBroadcastListener() {
    final collectionRef =
        FirebaseFirestore.instance.collection('broadcast_voice');

    _broadcastSubscription = collectionRef
        .orderBy('CreatedAt', descending: true)
        .snapshots()
        .listen((querySnapshot) {
      setState(() {
        _broadcasts = querySnapshot.docs.map((doc) {
          return {
            'audioFiles': List<String>.from(doc['AudioFiles']),
            'coordinator': doc['Coordinator'],
            'createdAt': doc['CreatedAt'], // Optional for display or sorting
          };
        }).toList();
      });
    });
  }
  StreamSubscription? _audioFilesSubscription;
  void _setupAudioFilesListener() {
    final collectionRef =
        FirebaseFirestore.instance.collection('Study_material');

    _audioFilesSubscription = collectionRef.snapshots().listen((querySnapshot) {
      try {
        setState(() {
          audioFiles = querySnapshot.docs
              .map((doc) => (doc['AudioFiles'] as List).cast<String>())
              .expand((x) => x)
              .toList();
        });
      } catch (e) {
        print("Error processing audio files: $e");
      }
    });
  }
  void _playAudio_simple(String audioUrl) {
    if (_currentPlayingAudioUrl == audioUrl) {
      // If the same audio is clicked, pause it
      setState(() {
        _currentPlayingAudioUrl = null; // Reset to not playing
      });
    } else {
      setState(() {
        _currentPlayingAudioUrl = audioUrl; // Track currently playing audio URL
      });
    }
  }








  Future<void> _playAudio_stats(String audioUrl) async {
    if (_currentPlayingAudioUrl == audioUrl) {
      // If the same audio is clicked, pause it
      setState(() {
        _currentPlayingAudioUrl = null; // Reset to not playing
      });
    } else {
      setState(() {
        _currentPlayingAudioUrl = audioUrl; // Track currently playing audio URL
        audioPlayedCount++; // Increment play count
      });
      await updateAudioCountInFirestore(audioPlayedCount);
    }
  }

  void _stopCurrentAudio() {
    if (_currentAudioPlayer != null) {
      _currentAudioPlayer?.pause(); // Pause the current audio
      _currentAudioPlayer?.dispose();
      _currentAudioPlayer = null;
      _currentPlayingAudioUrl = null; // Reset the currently playing audio URL
    }
  }

  Future<void> storeParticipantStats() async {
    final participantId =
        meeting.localParticipant.id; // Retrieve participant ID

    // Format the current time as HH:mm:ss

    final data = {
      'displayName': widget.displayName,
      'joinTime':
          FieldValue.serverTimestamp(), // Store current time as a Timestamp
      'audioPlayedCount': 0, // Initialize audio played count to zero
      'Q_Marks': 20, // Initialize quiz marks
      'isLocal': true, // Set to true since this is the local participant
    };

    final DocumentReference participantDoc =
        FirebaseFirestore.instance.collection('Stats').doc(participantId);

    await participantDoc.set(data, SetOptions(merge: true));
    print('Participant stats stored for participant $participantId');
  }

  Future<void> updateAudioCountInFirestore(int playCount) async {
    final participantId =
        meeting.localParticipant.id; // Retrieve participant ID
    final DocumentReference participantDoc =
        FirebaseFirestore.instance.collection('Stats').doc(participantId);

    // Update the audio played count
    await participantDoc.update({'audioPlayedCount': playCount});
    print(
        'Updated audio played count for participant $participantId: $playCount');
  }

  @override
  Widget build(BuildContext context) {
    final principalProvider = Provider.of<PrincipalProvider>(context);
    //Get statusbar height
    final statusbarHeight = MediaQuery.of(context).padding.top;
    bool isWebMobile = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) {
          return;
        }
        _onWillPopScope();
      },
      child: _joined
          ? SafeArea(
              child: Scaffold(
                  backgroundColor: Theme.of(context).primaryColor,
                  body: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      !isWebMobile &&
                              (kIsWeb || Platform.isMacOS || Platform.isWindows)
                          ? WebMeetingAppBar(
                              meeting: meeting,
                              token: widget.token,
                              recordingState: recordingState,
                              isMicEnabled: audioStream != null,
                              isCamEnabled: videoStream != null,
                              isLocalScreenShareEnabled: shareStream != null,
                              isRemoteScreenShareEnabled:
                                  remoteParticipantShareStream != null,
                            )
                          : MeetingAppBar(
                              meeting: meeting,
                              token: widget.token,
                              recordingState: recordingState,
                              isFullScreen: fullScreen,
                            ),
                      const Divider(),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Remaining Time: $_remainingMinutes minutes',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      _broadcasts.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10.0),
                                child: Text(
                                  'No Announcements Made Till Now.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                // Class Teacher Grid
                                ListView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  shrinkWrap: true,
                                  itemCount: _broadcasts.length,
                                  itemBuilder: (context, index) {
                                    final broadcast = _broadcasts[index];

                                    return Card(
                                      color: Colors.white,
                                      elevation: 0,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Coordinator Name (Optional)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8.0,
                                                horizontal: 16.0),
                                            child: Text(
                                              'Coordinator: ${broadcast['coordinator']}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          if (broadcast['audioFiles']
                                              .isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children:
                                                    broadcast['audioFiles']
                                                        .map<Widget>(
                                                            (audioUrl) {
                                                  return AudioPlayerWidget(
                                                    audioUrl: audioUrl,
                                                    onPlay: () =>
                                                        _playAudio_simple(
                                                            audioUrl),
                                                    onStop: _stopCurrentAudio,
                                                    isPlaying:
                                                        _currentPlayingAudioUrl ==
                                                            audioUrl,
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                      SizedBox(height: 10),
                      Consumer<RoleProvider>(
                        builder: (context, roleProvider, child) {
                          if (roleProvider.isPrincipal) {
                            return Center(
                              child: buildCreateMoreButton(),
                            );
                          } else {
                            // Return an empty container if the conditions are not met
                            return SizedBox.shrink();
                          }
                        },
                      ),
                      Expanded(
                          child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 15.0, vertical: 8.0),
                        child: Flex(
                          direction: ResponsiveValue<Axis>(context,
                              conditionalValues: [
                                Condition.equals(
                                    name: MOBILE, value: Axis.vertical),
                                Condition.largerThan(
                                    name: MOBILE, value: Axis.horizontal),
                              ]).value!,
                          children: [
                            ConferenseScreenShareView(meeting: meeting),
                            Expanded(
                              child:
                                  ConferenceParticipantGrid(meeting: meeting),
                            ),
                          ],
                        ),
                      )),
                      Column(
                        children: [
                          const Divider(),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 300),
                            crossFadeState: !fullScreen
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            secondChild: const SizedBox.shrink(),
                            firstChild: MeetingActionBar(
                              isMicEnabled: audioStream != null,
                              isCamEnabled: videoStream != null,
                              isScreenShareEnabled: shareStream != null,
                              recordingState: recordingState,
                              // Called when Call End button is pressed
                              onCallEndButtonPressed: () {
                                meeting.end();

                                Future.delayed(
                                    const Duration(milliseconds: 500), () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            SplashScreen()), // Navigate to TeacherScreen
                                  );
                                });
                              },

                              onCallLeaveButtonPressed: () {
                                meeting.leave();
                                Future.delayed(
                                    const Duration(milliseconds: 500), () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            SplashScreen()), // Navigate to TeacherScreen
                                  );
                                });
                              },
                              // Called when mic button is pressed
                              onMicButtonPressed: () {
                                if (audioStream != null) {
                                  meeting.muteMic();
                                } else {
                                  meeting.unmuteMic();
                                }
                              },
                              // Called when camera button is pressed
                              onCameraButtonPressed: () {
                                if (videoStream != null) {
                                  meeting.disableCam();
                                } else {
                                  meeting.enableCam();
                                }
                              },

                              onSwitchMicButtonPressed: (details) async {
                                List<AudioDeviceInfo>? outputDevice =
                                    await VideoSDK.getAudioDevices();

                                double bottomMargin =
                                    (70.0 * outputDevice!.length);
                                final screenSize = MediaQuery.of(context).size;
                                await showMenu(
                                  context: context,
                                  color: black700,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  position: RelativeRect.fromLTRB(
                                    screenSize.width -
                                        details.globalPosition.dx,
                                    details.globalPosition.dy - bottomMargin,
                                    details.globalPosition.dx,
                                    (bottomMargin),
                                  ),
                                  items: outputDevice.map((e) {
                                    return PopupMenuItem(
                                      padding: EdgeInsets.zero,
                                      value: e,
                                      child: Container(
                                        color: e.deviceId ==
                                                meeting
                                                    .selectedSpeaker?.deviceId
                                            ? Color.fromRGBO(109, 110, 113, 1)
                                            : Colors.transparent,
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: Padding(
                                            padding: EdgeInsets.fromLTRB(16, 10,
                                                5, 10), // Ensure no padding
                                            child: Text(e.label),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  elevation: 8.0,
                                ).then((value) {
                                  if (value != null) {
                                    meeting.switchAudioDevice(value);
                                  }
                                });
                              },

                              onChatButtonPressed: () {
                                setState(() {
                                  showChatSnackbar = false;
                                });
                                showModalBottomSheet(
                                  context: context,
                                  constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.of(context).size.height -
                                              statusbarHeight),
                                  isScrollControlled: true,
                                  builder: (context) => ChatView(
                                      key: const Key("ChatScreen"),
                                      meeting: meeting),
                                ).whenComplete(() {
                                  setState(() {
                                    showChatSnackbar = true;
                                  });
                                });
                              },

                              // Called when more options button is pressed
                              onMoreOptionSelected: (option) {
                                // Showing more options dialog box
                                if (option == "screenshare") {
                                  if (remoteParticipantShareStream == null) {
                                    if (shareStream == null) {
                                      meeting.enableScreenShare();
                                    } else {
                                      meeting.disableScreenShare();
                                    }
                                  } else {
                                    showSnackBarMessage(
                                        message:
                                            "Someone is already presenting",
                                        context: context);
                                  }
                                } else if (option == "recording") {
                                  if (recordingState == "RECORDING_STOPPING") {
                                    showSnackBarMessage(
                                        message:
                                            "Recording is in stopping state",
                                        context: context);
                                  } else if (recordingState ==
                                      "RECORDING_STARTED") {
                                    meeting.stopRecording();
                                  } else if (recordingState ==
                                      "RECORDING_STARTING") {
                                    showSnackBarMessage(
                                        message:
                                            "Recording is in starting state",
                                        context: context);
                                  } else {
                                    meeting.startRecording();
                                  }
                                } else if (option == "participants") {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: false,
                                    builder: (context) =>
                                        ParticipantList(meeting: meeting),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Consumer<RoleProvider>(
                          builder: (context, roleProvider, child) {
                        if (roleProvider.isTeacher) {
                          return Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lectures List',
                                  style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white),
                                ),
                                // LIST VIEW CODE
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('Study_material')
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }
                                    if (!snapshot.hasData ||
                                        snapshot.data!.docs.isEmpty) {
                                      return Row(children: [
                                        Center(
                                          child: Text(
                                            'No lectures found.',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),

                                        /* HIDE UPLOADING
                                        Center(
                                          child: FloatingActionButton(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (context) =>
                                                        const Create_lecture()),
                                              );
                                            },
                                            backgroundColor:
                                                const Color(0xFF044B89),
                                            child: SvgPicture.asset(
                                              'assets/FAB.svg', // Replace with your custom SVG
                                              width:
                                                  40, // Adjust the size as needed
                                              height:
                                                  40, // Adjust the size as needed
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),

                                        */
                                      ]);
                                    }

                                    final lectureDocs = snapshot.data!.docs;

                                    return ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: lectureDocs.length,
                                      itemBuilder: (context, index) {
                                        final lecture = lectureDocs[index];
                                        final lectureName =
                                            lecture['TopicName'] ?? 'No Name';
                                        final lectureDescription =
                                            lecture['TopicDescription'] ??
                                                'No Description';
                                        final audioFiles =
                                            lecture['AudioFiles'] ?? [];
                                        final status =
                                            lecture['Status'] ?? 'Approved';

                                        return Card(
                                          color: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            side: BorderSide(
                                              color:
                                                  Colors.grey.withOpacity(0.2),
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ListTile(
                                                title: Text(
                                                  'Lecture Name',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  lectureName,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        shape:
                                                            const StadiumBorder(),
                                                        backgroundColor:
                                                            Colors.blue,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 16,
                                                          vertical: 8,
                                                        ),
                                                      ),
                                                      onPressed: () {},
                                                      child: Text(
                                                        status,
                                                        style:
                                                            GoogleFonts.poppins(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () async {
                                                        // Delete the lecture
                                                        await FirebaseFirestore
                                                            .instance
                                                            .collection(
                                                                'Study_material')
                                                            .doc(lecture.id)
                                                            .delete();
                                                      },
                                                      icon: const Icon(
                                                        Icons.delete,
                                                        color: Colors.red,
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              ListTile(
                                                title: Text(
                                                  'Lecture Description',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  lectureDescription,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              ListTile(
                                                title: Text(
                                                  'Lecture Audio Files',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children:
                                                      List<Widget>.generate(
                                                          audioFiles.length,
                                                          (audioIndex) {
                                                    final audioUrl =
                                                        audioFiles[audioIndex];
                                                    return Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 8),
                                                      child: AudioPlayerWidget(
                                                        audioUrl: audioUrl,
                                                        onPlay: () =>
                                                            _playAudio_simple(
                                                                audioUrl),
                                                        onStop: () =>
                                                            _stopCurrentAudio(),
                                                        isPlaying:
                                                            _currentPlayingAudioUrl ==
                                                                audioUrl,
                                                      ),
                                                    );
                                                  }),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        } else if (roleProvider.isStudent) {
                          return Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  // Class Teacher Grid
                                  principalProvider.teacherCards.isEmpty
                                      ? Center(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                top: 50.0),
                                            child: Text(
                                              'No approved content available.',
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          shrinkWrap: true,
                                          itemCount: principalProvider
                                              .teacherCards.length,
                                          itemBuilder: (context, index) {
                                            final card = principalProvider
                                                .teacherCards[index];

                                            return Card(
                                              color: Colors.white,
                                              elevation: 0,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
                                                        16.0,
                                                        16.0,
                                                        16.0,
                                                        8.0), // Top-left padding
                                                    child: Text(
                                                      'List Of Lectures',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  if (card['audioFiles']
                                                      .isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16.0),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children:
                                                            card['audioFiles']
                                                                .map<Widget>(
                                                                    (audioUrl) {
                                                          return AudioPlayerWidget(
                                                            audioUrl: audioUrl,
                                                            onPlay: () =>
                                                                _playAudio_stats(
                                                                    audioUrl),
                                                            onStop:
                                                                _stopCurrentAudio,
                                                            isPlaying:
                                                                _currentPlayingAudioUrl ==
                                                                    audioUrl,
                                                          );
                                                        }).toList(),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),

                                  SizedBox(height: 20),
                                  // Information Section
                                  // QUIZZ SECTION UPDATE THIS TO HAVE QUIZ UI WITH TIMER AUTO SHIFT
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Quiz Screen',
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          // Ensures the QuizWidget fits within the available space
                                          height: 250,
                                          child: QuizWidget(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          // Return an empty container if the conditions are not met
                          return const SizedBox.shrink();
                        }
                      }),
                    ],
                  )),
            )
          : const WaitingToJoin(),
    );
  }

  Widget buildCreateMoreButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      ),
      icon: const Icon(
        Icons.video_camera_front_outlined,
        color: Colors.white,
        size: 25,
      ),
      label: Text(
        "Create More Rooms",
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      onPressed: () async {
        meeting.leave();
        Future.delayed(const Duration(milliseconds: 500), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => TeacherScreen()),
          );
        });
      },
    );
  }

  void registerMeetingEvents(Room _meeting) {
    // Called when joined in meeting
    _meeting.on(
      Events.roomJoined,
      () {
        setState(() {
          meeting = _meeting;
          _joined = true;
        });

        if (kIsWeb || Platform.isWindows || Platform.isMacOS) {
          _meeting.switchAudioDevice(widget.selectedAudioOutputDevice!);
        }

        subscribeToChatMessages(_meeting);
      },
    );

    // Called when meeting is ended
    _meeting.on(Events.roomLeft, (String? errorMsg) {
      if (errorMsg != null) {
        showSnackBarMessage(
            message: "Meeting left due to $errorMsg !!", context: context);
      }
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => TeacherScreen()),
          (route) => false);
    });

    // Called when recording is started
    _meeting.on(Events.recordingStateChanged, (String status) {
      showSnackBarMessage(
          message:
              "Meeting recording ${status == "RECORDING_STARTING" ? "is starting" : status == "RECORDING_STARTED" ? "started" : status == "RECORDING_STOPPING" ? "is stopping" : "stopped"}",
          context: context);

      setState(() {
        recordingState = status;
      });
    });

    // Called when stream is enabled
    _meeting.localParticipant.on(Events.streamEnabled, (Stream _stream) {
      if (_stream.kind == 'video') {
        setState(() {
          videoStream = _stream;
        });
      } else if (_stream.kind == 'audio') {
        setState(() {
          audioStream = _stream;
        });
      } else if (_stream.kind == 'share') {
        setState(() {
          shareStream = _stream;
        });
      }
    });

    // Called when stream is disabled
    _meeting.localParticipant.on(Events.streamDisabled, (Stream _stream) {
      if (_stream.kind == 'video' && videoStream?.id == _stream.id) {
        setState(() {
          videoStream = null;
        });
      } else if (_stream.kind == 'audio' && audioStream?.id == _stream.id) {
        setState(() {
          audioStream = null;
        });
      } else if (_stream.kind == 'share' && shareStream?.id == _stream.id) {
        setState(() {
          shareStream = null;
        });
      }
    });

    // Called when presenter is changed
    _meeting.on(Events.presenterChanged, (_activePresenterId) {
      Participant? activePresenterParticipant =
          _meeting.participants[_activePresenterId];

      // Get Share Stream
      Stream? _stream = activePresenterParticipant?.streams.values
          .singleWhere((e) => e.kind == "share");

      setState(() => remoteParticipantShareStream = _stream);
    });

    _meeting.on(
        Events.error,
        (error) => {
              showSnackBarMessage(
                  message: error['name'].toString() +
                      " :: " +
                      error['message'].toString(),
                  context: context)
            });
  }

  void subscribeToChatMessages(Room meeting) {
    meeting.pubSub.subscribe("CHAT", (message) {
      if (message.senderId != meeting.localParticipant.id) {
        if (mounted) {
          if (showChatSnackbar) {
            showSnackBarMessage(
                message: message.senderName + ": " + message.message,
                context: context);
          }
        }
      }
    });
  }

  Future<bool> _onWillPopScope() async {
    meeting.leave();

    Future.delayed(const Duration(milliseconds: 500), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => SplashScreen()),
      );
    });
    return true;
  }

  @override
  void dispose() {
    _broadcastSubscription
        ?.cancel(); // Stop the listener when the widget is disposed
    _audioFilesSubscription
        ?.cancel(); // Stop the listener when the widget is disposed

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
    _timer?.cancel(); // Cancel the timer on dispose
  }
}

class QuizWidget extends StatefulWidget {
  @override
  _QuizWidgetState createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<QuizWidget> {
  final PageController _pageController = PageController();
  int _currentQuestionIndex = 0;
  Timer? _timer;
  int _remainingTime = 15;
  bool _quizStarted = false;
  String? _selectedChoice;

  final List<Map<String, dynamic>> _questions = [
    {
      'question': 'What is photography?',
      'choices': [
        'Drawing with light',
        'Painting with water',
        'Writing stories',
        'Printing documents'
      ],
      'answer': 'Drawing with light',
    },
    {
      'question': 'Which is NOT a type of photography?',
      'choices': ['Portrait', 'Landscape', 'Cooking', 'Wildlife'],
      'answer': 'Cooking',
    },
    {
      'question': 'WHat is used to capture the photos?',
      'choices': ['Phone', 'Camera', 'Microphone', 'Telescope'],
      'answer': 'Camera',
    },
    {
      'question': 'What controls the brightness of a photo?',
      'choices': ['ISO', 'Zoom', 'Shutter', 'Flash'],
      'answer': 'ISO',
    },
    {
      'question': 'What does a tripod do?',
      'choices': [
        'Hold the camera steady',
        'Change camera settings',
        'Clean the lens',
        'Store photos'
      ],
      'answer': 'Hold the camera steady',
    },
    {
      'question': 'Which light is best for outdoor photography?',
      'choices': ['Morning and evening', 'Noon', 'Night', 'Artificial Light'],
      'answer': 'Morning and evening',
    },
    {
      'question': 'What is a zoom lens used for?',
      'choices': [
        'Taking close-up shots from far away',
        'Adding filters',
        'Fixing blurry images',
        'Editing photos'
      ],
      'answer': 'Taking close-up shots from far away',
    },
    {
      'question': 'What is a common use of portrait photography?',
      'choices': [
        'Shooting buildings',
        'Capturing nature',
        'Photographing animals',
        'Taking selfies'
      ],
      'answer': 'Taking selfies',
    },
    {
      'question': 'What is essential for low-light photography?',
      'choices': ['Flash', 'Tripod', 'Zoom Lens', 'Filter'],
      'answer': 'Flash',
    },
    {
      'question': 'What does editing software do?',
      'choices': [
        'Improve photo quality',
        'Capture photos',
        'Print photos',
        'Store files'
      ],
      'answer': 'Improve photo quality',
    },
    {
      'question': 'What should you clean regularly in your camera?',
      'choices': ['Lens', 'Battery', 'Flash', 'Shutter'],
      'answer': 'Lens',
    },
    {
      'question': 'What is "composition" in photography?',
      'choices': [
        'How a photo is arranged',
        'The color of the photo',
        'The size of the photo',
        'The brightness of the photo'
      ],
      'answer': 'How a photo is arranged',
    },
    {
      'question': 'Which tool adjusts color tones?',
      'choices': ['Filters', 'Shutter', 'Lens Cap', 'Battery'],
      'answer': 'Filters',
    },
    {
      'question': 'What is the first step to learn photography?',
      'choices': [
        'Understanding the camera',
        'Buying a tripod',
        'Printing photos',
        'Learning to edit'
      ],
      'answer': 'Understanding the camera',
    },
    {
      'question': 'What does a "wide-angle lens" capture?',
      'choices': [
        'Large Areas',
        'Tiny Objects',
        'Close Up Shoots',
        'Distant Object'
      ],
      'answer': 'Large Areas',
    },
  ];

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startQuiz() {
    setState(() {
      _quizStarted = true;
      _startTimer();
    });
  }

  void _startTimer() {
    _remainingTime = 15;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTime > 0) {
          _remainingTime--;
        } else {
          _goToNextQuestion();
        }
      });
    });
  }

  void _goToNextQuestion() {
    _timer?.cancel();
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedChoice = null;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _startTimer();
    } else {
      // Quiz ends
      _timer?.cancel();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Quiz Completed',
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
          ),
          content: const Text('You have finished the quiz.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _currentQuestionIndex = 0;
                  _selectedChoice = null;
                  _pageController.jumpToPage(0);
                  _quizStarted = false;
                });
              },
              child: Text(
                'Restart',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _onOptionSelected(String choice) {
    setState(() {
      _selectedChoice = choice;
    });
    Future.delayed(const Duration(seconds: 2), () {
      _goToNextQuestion();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _quizStarted
        ? SizedBox(
            height: 400,
            child: Column(
              children: [
                Text(
                  'Time Remaining: $_remainingTime seconds',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 200,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      final question = _questions[index];
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question['question'],
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10.0,
                              runSpacing: 10.0,
                              children:
                                  question['choices'].map<Widget>((choice) {
                                final isSelected = choice == _selectedChoice;
                                final isCorrect = choice == question['answer'];
                                Color? backgroundColor;
                                if (isSelected) {
                                  backgroundColor =
                                      isCorrect ? Colors.green : Colors.red;
                                } else {
                                  backgroundColor = Colors.white;
                                }
                                return GestureDetector(
                                  onTap: _selectedChoice == null
                                      ? () => _onOptionSelected(choice)
                                      : null,
                                  child: Container(
                                    width:
                                        MediaQuery.of(context).size.width / 2 -
                                            30,
                                    padding: const EdgeInsets.all(10.0),
                                    decoration: BoxDecoration(
                                      color: backgroundColor,
                                      borderRadius: BorderRadius.circular(8.0),
                                      border: Border.all(color: Colors.grey),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      choice,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        : Column(children: [
            Divider(),
            Center(
              child: Text(
                'Quiz is Based on Lecture #01',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Divider(),
            Center(
              child: ElevatedButton(
                onPressed: _startQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: Text(
                  'Start Quiz',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ]);
  }
}
/*

class Create_lecture extends StatefulWidget {
  const Create_lecture({super.key});

  @override
  State<Create_lecture> createState() => _Create_LectureState();
}

class _Create_LectureState extends State<Create_lecture> {
  final CreateTopicProvider assignmentProvider = CreateTopicProvider();

  final List<File> _selectedFiles = [];
  bool _isUploading = false;

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a'],
      );

      if (result != null) {
        setState(() {
          _selectedFiles
              .addAll(result.paths.map((path) => File(path!)).toList());
        });
      } else {
        print("No files selected.");
      }
    } catch (e) {
      print("Error picking files: $e");
    }
  }

  Future<List<String>> _uploadFilesToFirebase() async {
    List<String> downloadUrls = [];
    const teachername = 'dummy teacher';

    try {
      for (var file in _selectedFiles) {
        final fileName = file.path.split('/').last;
        if (['.mp3', '.wav', '.m4a'].any((ext) => fileName.endsWith(ext))) {
          final ref = FirebaseStorage.instance
              .ref()
              .child('study_materials/$teachername/$fileName');
          final uploadTask = ref.putFile(file);

          // Wait for the upload to complete and get the URL
          final snapshot = await uploadTask;
          final downloadUrl = await snapshot.ref.getDownloadURL();
          downloadUrls.add(downloadUrl);
        } else {
          print("Unsupported file format for $fileName");
        }
      }
    } catch (e) {
      print("Error uploading files: $e");
    }

    return downloadUrls;
  }

  Future<void> _saveToFirestore(CreateTopicProvider assignmentProvider) async {
    setState(() {
      _isUploading = true;
    });

    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    final audioUrls = await _uploadFilesToFirebase(); // Upload all files

    final docRef =
        FirebaseFirestore.instance.collection('Study_material').doc();
    await docRef.set({
      'TopicName': assignmentProvider.assignmentName,
      'ClassSelected': assignmentProvider.selectedClass,
      'SubjectSelected': assignmentProvider.selectedSubject,
      'TopicDescription': assignmentProvider.instructions,
      'TeacherId': teacherId,
      'AudioFiles': audioUrls, // Save all audio URLs as an array
      'CreatedAt': FieldValue.serverTimestamp(),
      'Status': assignmentProvider.status,
    });

    setState(() {
      _isUploading = false;
      _selectedFiles.clear();
    });

    _showSnackbar_connection(context, 'Topic added successfully!');
  }

  void _showSnackbar_connection(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: GoogleFonts.poppins().fontFamily,
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.green.withOpacity(0.8),
        duration: const Duration(seconds: 5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(10),
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90), // Set the height
        child: AppBar(
          leading: IconButton(
            icon: SvgPicture.asset(
              'assets/back_icon.svg',
              width: 25, // Adjust the size as needed
              height: 25, // Adjust the size as needed
              color: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          title: Text(
            "Upload Lectures",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF044B89),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[100],
                        hintText: "Lecture Name",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(width: 1, color: Colors.black),
                        ),
                      ),
                      onChanged: (value) {
                        assignmentProvider.setTopicName(value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[100],
                        hintText: "Lecture Description",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(width: 1, color: Colors.black),
                        ),
                      ),
                      maxLines: 5,
                      onChanged: (value) {
                        assignmentProvider.setInstructions(value);
                      },
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _pickFiles,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.black12,
                            style: BorderStyle.solid,
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF044B89),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedFiles.isNotEmpty
                                  ? "${_selectedFiles.length} file(s) selected"
                                  : "Study Material(s)",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 46),
                    Center(
                      child: ElevatedButton(
                        onPressed: _isUploading
                            ? null
                            : () => _saveToFirestore(assignmentProvider),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF044B89),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _isUploading ? "Submitting..." : "Upload",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
*/

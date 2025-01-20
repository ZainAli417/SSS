import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:videosdk/videosdk.dart'; // Make sure to import the Video SDK package

class StatsManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Pushes participant stats to Firestore
  Future<void> pushParticipantStats(Participant participant) async {
    try {
      // Fetch stats using the provided `getStats` function
      final List<dynamic>? videoStats = participant.getVideoStats();
      final List<dynamic>? audioStats = participant.getAudioStats();
      final List<dynamic>? shareStats = participant.getShareStats();

      // Prepare data to push to Firestore
      final Map<String, dynamic> data = {
        'displayName': participant.displayName,
        'isLocal': participant.isLocal,
        'joinTime': DateTime.now().toIso8601String(), // Timestamp for join
        'micEnabled': participant.metaData?['micEnabled'] ?? false,
        'cameraEnabled': participant.metaData?['cameraEnabled'] ?? false,
        'videoStats': videoStats,
        'audioStats': audioStats,
        'shareStats': shareStats,
      };

      // Create the Firestore document path: STATS/participantId
      final DocumentReference participantDoc =
      _firestore.collection('Stats').doc(participant.id);

      // Push the data to Firestore
      await participantDoc.set(data, SetOptions(merge: true));
      print('Stats pushed successfully for participant ${participant.id}');
    } catch (e) {
      print('Error pushing stats to Firestore: $e');
    }
  }
}

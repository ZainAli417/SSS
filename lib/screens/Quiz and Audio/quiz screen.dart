import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final VoidCallback onPlay; // Callback to handle play action
  final VoidCallback onStop; // Callback to handle play action
  final bool isPlaying; // Track if this audio is currently playing

  const AudioPlayerWidget({
    Key? key,
    required this.audioUrl,
    required this.onPlay,
    required this.onStop,
    required this.isPlaying,
  }) : super(key: key);

  @override
  _AudioPlayerWidgetState createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  bool _isLooping = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.setUrl(widget.audioUrl);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (_audioPlayer.playing) return; // Prevent duplicate play calls
    await _audioPlayer.play();
  }

  Future<void> _pauseAudio() async {
    if (!_audioPlayer.playing) return; // Prevent duplicate pause calls
    await _audioPlayer.pause();
  }

  @override
  Widget build(BuildContext context) {
    // Synchronize the audio player with the parent's isPlaying state
    if (widget.isPlaying) {
      _playAudio();
    } else {
      _pauseAudio();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.07),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              widget.isPlaying ? Icons.pause : Icons.play_arrow,
              color: widget.isPlaying ? Colors.red : Colors.green,
            ),
            onPressed: () {
              if (widget.isPlaying) {
                widget.onPlay(); // Notify the parent to play this audio

              } else {
                widget.onPlay(); // Notify the parent to play this audio
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Expanded(
            child: StreamBuilder<Duration?>(
              stream: _audioPlayer.positionStream,
              builder: (context, snapshot) {
                final currentPosition = snapshot.data ?? Duration.zero;
                final totalDuration = _audioPlayer.duration ?? Duration.zero;

                return SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: currentPosition.inSeconds.toDouble(),
                    max: totalDuration.inSeconds.toDouble(),
                    min: 0,
                    activeColor: Colors.black,
                    inactiveColor: Colors.black12,
                    onChanged: (value) async {
                      await _audioPlayer.seek(Duration(seconds: value.toInt()));
                    },
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(
              _isLooping ? Icons.loop : Icons.loop_outlined,
              color: _isLooping ? Colors.red : Colors.black,
            ),
            onPressed: () async {
              setState(() {
                _isLooping = !_isLooping;
              });
              await _audioPlayer.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          StreamBuilder<Duration?>(
            stream: _audioPlayer.positionStream,
            builder: (context, snapshot) {
              final currentPosition = snapshot.data ?? Duration.zero;
              final totalDuration = _audioPlayer.duration ?? Duration.zero;
              final remainingTime = totalDuration - currentPosition;

              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _formatDuration(remainingTime),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }
}

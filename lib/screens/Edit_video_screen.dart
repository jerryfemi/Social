import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_trimmer/video_trimmer.dart';

class EditVideoScreen extends StatefulWidget {
  final File file;
  const EditVideoScreen({super.key, required this.file});

  @override
  State<EditVideoScreen> createState() => _EditVideoScreenState();
}

class _EditVideoScreenState extends State<EditVideoScreen> {
  final Trimmer _trimmer = Trimmer();

  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  // load video
  void _loadVideo() {
    _trimmer.loadVideo(videoFile: widget.file);
  }

  // saveVideo
  Future<void> _saveVideo() async {
    setState(() => _isSaving = true);

    // save video
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (outputPath) {
        setState(() => _isSaving = false);
        if (outputPath != null && mounted) {
          // Return the trimmed video path to the previous screen
          context.pop(outputPath);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trim Video'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving) const LinearProgressIndicator(),

              // Video Preview
              Expanded(child: VideoViewer(trimmer: _trimmer)),

              // Trimmer Slider
              TrimViewer(
                trimmer: _trimmer,
                viewerHeight: 50,
                viewerWidth: MediaQuery.of(context).size.width,
                maxVideoLength: const Duration(seconds: 30),
                onChangeStart: (startValue) => _startValue = startValue,
                onChangeEnd: (endValue) => _endValue = endValue,
                onChangePlaybackState: (isPlaying) {
                  setState(() => _isPlaying = isPlaying);
                },
              ),
              const SizedBox(height: 20),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // play/pause button
                  IconButton(
                    onPressed: () async {
                      bool onChangePlaybackState = await _trimmer
                          .videoPlaybackControl(
                            startValue: _startValue,
                            endValue: _endValue,
                          );
                      setState(() => _isPlaying = onChangePlaybackState);
                    },
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveVideo,
                child: Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social/services/audio_service.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int duration;
  final bool isSender;
  final Color bubbleColor;
  final String textTime;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.duration,
    required this.isSender,
    required this.bubbleColor,
    required this.textTime,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble>
    with SingleTickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _durationInitialized = false;

  // Seek state
  bool _isSeeking = false;
  double _seekProgress = 0.0;
  late AnimationController _scrubberScaleController;
  late Animation<double> _scrubberScaleAnimation;

  // Key to get waveform width
  final GlobalKey _waveformKey = GlobalKey();
  double _waveformWidth = 150; // Default fallback

  @override
  void initState() {
    super.initState();
    // Use widget duration as initial estimate
    _totalDuration = Duration(seconds: widget.duration);

    // Scrubber animation controller
    _scrubberScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scrubberScaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _scrubberScaleController, curve: Curves.easeOut),
    );

    // Get waveform width after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateWaveformWidth();
    });

    // Listen to actual duration from player (more accurate)
    _audioService.durationStream.listen((duration) {
      if (_audioService.isPlayingUrl(widget.audioUrl) && mounted) {
        setState(() {
          _totalDuration = duration;
          _durationInitialized = true;
        });
      }
    });

    // Listen to position changes
    _audioService.positionStream.listen((position) {
      if (_audioService.isPlayingUrl(widget.audioUrl) &&
          mounted &&
          !_isSeeking) {
        setState(() {
          _position = position;
          // Clamp position to not exceed duration
          if (_totalDuration.inMilliseconds > 0 &&
              _position.inMilliseconds > _totalDuration.inMilliseconds) {
            _position = _totalDuration;
          }
        });
      }
    });

    // Listen to player state changes
    _audioService.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying =
              state == PlayerState.playing &&
              _audioService.isPlayingUrl(widget.audioUrl);
        });

        // Reset position when completed
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          setState(() {
            _position = Duration.zero;
            _durationInitialized = false;
          });
        }
      }
    });
  }

  void _updateWaveformWidth() {
    final RenderBox? renderBox =
        _waveformKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      setState(() {
        _waveformWidth = renderBox.size.width;
      });
    }
  }

  @override
  void dispose() {
    _scrubberScaleController.dispose();
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play(widget.audioUrl);
    }
  }

  /// Calculate seek position from local x coordinate
  Duration _getSeekPosition(double localX, double width) {
    final percentage = (localX / width).clamp(0.0, 1.0);
    return Duration(
      milliseconds: (_totalDuration.inMilliseconds * percentage).toInt(),
    );
  }

  /// Handle seek start (tap down or drag start)
  void _onSeekStart(double localX, double width) {
    HapticFeedback.selectionClick();
    _scrubberScaleController.forward();

    final percentage = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _isSeeking = true;
      _seekProgress = percentage;
    });
  }

  /// Handle seek update (drag)
  void _onSeekUpdate(double localX, double width) {
    final percentage = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _seekProgress = percentage;
    });
  }

  /// Handle seek end - perform the actual seek
  Future<void> _onSeekEnd(double localX, double width) async {
    _scrubberScaleController.reverse();

    final seekPosition = _getSeekPosition(localX, width);

    setState(() {
      _isSeeking = false;
      _position = seekPosition;
    });

    // If this audio is currently loaded, seek it
    if (_audioService.isPlayingUrl(widget.audioUrl)) {
      await _audioService.seek(seekPosition);
    } else {
      // Start playing from the seek position
      await _audioService.play(widget.audioUrl);
      // Small delay to let the player initialize, then seek
      await Future.delayed(const Duration(milliseconds: 100));
      await _audioService.seek(seekPosition);
    }

    HapticFeedback.lightImpact();
  }

  /// Handle tap to seek
  Future<void> _onTapSeek(double localX, double width) async {
    HapticFeedback.selectionClick();

    final seekPosition = _getSeekPosition(localX, width);

    setState(() {
      _position = seekPosition;
    });

    if (_audioService.isPlayingUrl(widget.audioUrl)) {
      await _audioService.seek(seekPosition);
    } else {
      await _audioService.play(widget.audioUrl);
      await Future.delayed(const Duration(milliseconds: 100));
      await _audioService.seek(seekPosition);
    }

    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    // Use seek progress while seeking, otherwise use actual position
    final progress = _isSeeking
        ? _seekProgress
        : (_totalDuration.inMilliseconds > 0
              ? (_position.inMilliseconds / _totalDuration.inMilliseconds)
                    .clamp(0.0, 1.0)
              : 0.0);

    // Show seek position while seeking, otherwise show current position/duration
    final displayDuration = _isSeeking
        ? AudioService.formatDuration(
            (_totalDuration.inSeconds * _seekProgress).toInt(),
          )
        : (_isPlaying
              ? AudioService.formatDuration(_position.inSeconds)
              : AudioService.formatDuration(
                  _durationInitialized
                      ? _totalDuration.inSeconds
                      : widget.duration,
                ));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 250),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Waveform / Progress with seek support
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seekable waveform
                GestureDetector(
                  onTapUp: (details) {
                    _updateWaveformWidth();
                    _onTapSeek(details.localPosition.dx, _waveformWidth);
                  },
                  onHorizontalDragStart: (details) {
                    _updateWaveformWidth();
                    _onSeekStart(details.localPosition.dx, _waveformWidth);
                  },
                  onHorizontalDragUpdate: (details) {
                    _onSeekUpdate(details.localPosition.dx, _waveformWidth);
                  },
                  onHorizontalDragEnd: (details) {
                    // Use the current seek progress to calculate final position
                    _onSeekEnd(_seekProgress * _waveformWidth, _waveformWidth);
                  },
                  child: AnimatedBuilder(
                    animation: _scrubberScaleAnimation,
                    builder: (context, child) {
                      return SizedBox(
                        key: _waveformKey,
                        height: 32, // Increased height for better touch target
                        child: CustomPaint(
                          painter: WaveformPainter(
                            progress: progress,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withValues(alpha: 0.4),
                            showScrubber: _isSeeking || _isPlaying,
                            scrubberScale: _scrubberScaleAnimation.value,
                          ),
                          size: const Size(double.infinity, 32),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 4),

                // Duration and time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        displayDuration,
                        key: ValueKey(displayDuration),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _isSeeking
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Text(
                      widget.textTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for waveform visualization with scrubber
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool showScrubber;
  final double scrubberScale;

  WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.showScrubber = false,
    this.scrubberScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 3.0;
    final spacing = 2.0;
    final barCount = (size.width / (barWidth + spacing)).floor();
    final progressBarCount = (barCount * progress).floor();

    // Predefined wave pattern (normalized 0-1)
    final wavePattern = [
      0.3,
      0.5,
      0.7,
      0.9,
      0.6,
      0.8,
      0.4,
      0.7,
      0.5,
      0.9,
      0.3,
      0.6,
      0.8,
      0.5,
      0.7,
      0.4,
      0.9,
      0.6,
      0.3,
      0.8,
      0.5,
      0.7,
      0.9,
      0.4,
      0.6,
      0.8,
      0.3,
      0.7,
      0.5,
      0.9,
    ];

    // Draw waveform bars
    for (int i = 0; i < barCount; i++) {
      final isActive = i < progressBarCount;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      // Get height from pattern (cycle through)
      final heightFactor = wavePattern[i % wavePattern.length];
      final barHeight =
          size.height * 0.75 * heightFactor; // Leave room for scrubber
      final top = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (barWidth + spacing), top, barWidth, barHeight),
        const Radius.circular(2),
      );

      canvas.drawRRect(rect, paint);
    }

    // Draw scrubber/thumb at current position
    if (showScrubber && progress > 0) {
      final scrubberX = size.width * progress;
      final scrubberRadius = 6.0 * scrubberScale;

      // Outer glow
      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(scrubberX, size.height / 2),
        scrubberRadius + 2,
        glowPaint,
      );

      // Main scrubber circle
      final scrubberPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(scrubberX, size.height / 2),
        scrubberRadius,
        scrubberPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.showScrubber != showScrubber ||
        oldDelegate.scrubberScale != scrubberScale;
  }
}

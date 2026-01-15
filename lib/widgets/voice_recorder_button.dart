import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:social/services/audio_service.dart';

class VoiceRecorderButton extends StatefulWidget {
  final Function(String path, int duration) onRecordingComplete;
  final VoidCallback? onRecordingStart;
  final VoidCallback? onRecordingCancel;

  const VoiceRecorderButton({
    super.key,
    required this.onRecordingComplete,
    this.onRecordingStart,
    this.onRecordingCancel,
  });

  @override
  State<VoiceRecorderButton> createState() => VoiceRecorderButtonState();
}

class VoiceRecorderButtonState extends State<VoiceRecorderButton>
    with TickerProviderStateMixin {
  // Use singleton - no dispose needed in widget
  final AudioService _audioService = AudioService();

  bool _isRecording = false;
  bool _isLocked = false;
  bool _isCancelled = false;
  bool _isHolding = false; // Track if user is holding (long press)
  int _recordingSeconds = 0;
  Timer? _timer;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;

  // Thresholds
  static const double _cancelThreshold = -100;
  static const double _lockThreshold = -80;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _lockIconController;
  late Animation<double> _lockIconPulseAnimation;
  late Animation<double> _lockIconBounceAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _lockIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _lockIconPulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _lockIconController, curve: Curves.easeInOut),
    );
    _lockIconBounceAnimation = Tween<double>(begin: 0.0, end: -8.0).animate(
      CurvedAnimation(parent: _lockIconController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _stopTimer();
    _pulseController.dispose();
    _lockIconController.dispose();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _resetState() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _isCancelled = false;
      _isHolding = false;
      _recordingSeconds = 0;
      _dragOffsetX = 0;
      _dragOffsetY = 0;
    });
  }

  Future<void> _startRecording({bool isHolding = false}) async {
    if (_isRecording) return;

    _stopTimer();
    final path = await _audioService.startRecording();

    if (path != null && mounted) {
      HapticFeedback.mediumImpact();

      setState(() {
        _isRecording = true;
        _isLocked = false;
        _isCancelled = false;
        _isHolding = isHolding;
        _recordingSeconds = 0;
        _dragOffsetX = 0;
        _dragOffsetY = 0;
      });

      _pulseController.repeat(reverse: true);
      if (isHolding) {
        _lockIconController.repeat(reverse: true);
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });

      widget.onRecordingStart?.call();
    }
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    if (!_isRecording) return;

    _stopTimer();
    _pulseController.stop();
    _pulseController.reset();
    _lockIconController.stop();
    _lockIconController.reset();

    final shouldCancel = cancel || _isCancelled;

    if (shouldCancel) {
      HapticFeedback.heavyImpact();
      await _audioService.cancelRecording();
      widget.onRecordingCancel?.call();
    } else {
      final result = await _audioService.stopRecording();
      if (result != null && result.path != null) {
        HapticFeedback.lightImpact();
        widget.onRecordingComplete(result.path!, result.duration);
      }
    }

    _resetState();
  }

  // Tap to start recording (locked mode immediately)
  void _onTap() {
    if (!_isRecording) {
      _startRecording(isHolding: false).then((_) {
        if (mounted && _isRecording) {
          setState(() {
            _isLocked = true;
          });
        }
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    // Start recording on drag start (swipe up gesture)
    if (!_isRecording) {
      _startRecording(isHolding: true);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isRecording) return;

    if (!mounted) return;
    setState(() {
      _dragOffsetX += details.delta.dx;
      _dragOffsetY += details.delta.dy;
      _dragOffsetX = _dragOffsetX.clamp(-150.0, 0.0);
      _dragOffsetY = _dragOffsetY.clamp(-120.0, 20.0);

      // Check if should cancel (swipe left)
      if (_dragOffsetX < _cancelThreshold && !_isLocked) {
        if (!_isCancelled) {
          HapticFeedback.selectionClick();
        }
        _isCancelled = true;
      } else if (_dragOffsetX >= _cancelThreshold) {
        _isCancelled = false;
      }

      // Check if should lock (swipe up) - only if not cancelled
      if (_dragOffsetY < _lockThreshold && !_isCancelled && !_isLocked) {
        HapticFeedback.mediumImpact();
        _isLocked = true;
        _isHolding = false;
        _lockIconController.stop();
        _lockIconController.reset();
        _dragOffsetX = 0;
        _dragOffsetY = 0;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isRecording) return;

    // If locked, don't stop - user needs to tap send or delete
    if (_isLocked) return;

    // If cancelled or dragged past threshold, cancel
    if (_isCancelled || _dragOffsetX < _cancelThreshold) {
      _stopRecording(cancel: true);
    } else {
      // Otherwise send the recording
      _stopRecording(cancel: false);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _startRecording(isHolding: true);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;

    if (!mounted) return;
    setState(() {
      _dragOffsetX += details.offsetFromOrigin.dx - _dragOffsetX;
      _dragOffsetY += details.offsetFromOrigin.dy - _dragOffsetY;
      _dragOffsetX = _dragOffsetX.clamp(-150.0, 0.0);
      _dragOffsetY = _dragOffsetY.clamp(-120.0, 20.0);

      // Check if should cancel (swipe left)
      if (_dragOffsetX < _cancelThreshold && !_isLocked) {
        if (!_isCancelled) {
          HapticFeedback.selectionClick();
        }
        _isCancelled = true;
      } else if (_dragOffsetX >= _cancelThreshold) {
        _isCancelled = false;
      }

      // Check if should lock (swipe up) - only if not cancelled
      if (_dragOffsetY < _lockThreshold && !_isCancelled && !_isLocked) {
        HapticFeedback.mediumImpact();
        _isLocked = true;
        _isHolding = false;
        _lockIconController.stop();
        _lockIconController.reset();
      }
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isRecording) return;

    if (_isLocked) return;

    if (_isCancelled || _dragOffsetX < _cancelThreshold) {
      _stopRecording(cancel: true);
    } else {
      _stopRecording(cancel: false);
    }
  }

  bool get isRecording => _isRecording;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: _isRecording
          ? _buildRecordingUI(context)
          : _buildMicButton(context),
    );
  }

  Widget _buildMicButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.mic,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildRecordingUI(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      child: Row(
        children: [
          // Delete button (only when locked)
          if (_isLocked) _buildDeleteButton(),

          // Main recording area
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isCancelled
                    ? Colors.red.withValues(alpha: 0.1)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: _isCancelled
                      ? Colors.red.withValues(alpha: 0.3)
                      : theme.colorScheme.secondary,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  _buildPulseDot(),
                  const SizedBox(width: 8),
                  _buildTimer(theme),
                  const Spacer(),
                  _buildSlideHint(theme),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Right side: Send button (when locked) or Pulsing mic (when holding)
          if (_isLocked) _buildSendButton(theme) else _buildPulsingMic(theme),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: () => _stopRecording(cancel: true),
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
      ),
    );
  }

  Widget _buildPulseDot() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.5),
                blurRadius: 4 * _pulseAnimation.value,
                spreadRadius: 2 * (_pulseAnimation.value - 1),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimer(ThemeData theme) {
    return Text(
      AudioService.formatDuration(_recordingSeconds),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _isCancelled ? Colors.red : theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildSlideHint(ThemeData theme) {
    if (_isLocked) {
      return Text(
        'Recording',
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }

    return Transform.translate(
      offset: Offset(_dragOffsetX * 0.3, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chevron_left,
            size: 18,
            color: _isCancelled
                ? Colors.red
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          Text(
            _isCancelled ? 'Release to cancel' : 'Slide to cancel',
            style: TextStyle(
              fontSize: 13,
              color: _isCancelled
                  ? Colors.red
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    return GestureDetector(
      onTap: () => _stopRecording(cancel: false),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.send, color: theme.colorScheme.onPrimary, size: 24),
      ),
    );
  }

  Widget _buildPulsingMic(ThemeData theme) {
    // Calculate lock progress (0 to 1 based on slide up)
    final lockProgress = (_dragOffsetY.abs() / _lockThreshold.abs()).clamp(
      0.0,
      1.0,
    );

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: 50,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Lock indicator above the mic button (only when holding and not locked)
              if (_isHolding && !_isLocked && !_isCancelled)
                Positioned(
                  bottom: 55 + (_dragOffsetY * 0.5).abs(),
                  child: AnimatedBuilder(
                    animation: _lockIconController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _lockIconBounceAnimation.value),
                        child: Transform.scale(
                          scale:
                              _lockIconPulseAnimation.value +
                              (lockProgress * 0.3),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                theme.colorScheme.surfaceContainerHighest,
                                theme.colorScheme.primary,
                                lockProgress,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.3 + (lockProgress * 0.4),
                                  ),
                                  blurRadius: 8 + (lockProgress * 8),
                                  spreadRadius: lockProgress * 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              lockProgress > 0.8 ? Icons.lock : Icons.lock_open,
                              color: Color.lerp(
                                theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                theme.colorScheme.onPrimary,
                                lockProgress,
                              ),
                              size: 18 + (lockProgress * 4),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              // Arrow pointing up (slide up hint)
              if (_isHolding && !_isLocked && !_isCancelled)
                Positioned(
                  bottom: 48,
                  child: AnimatedOpacity(
                    opacity: lockProgress < 0.5 ? 0.6 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ),
              // Main mic button
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Transform.translate(
                  offset: Offset(_dragOffsetX * 0.1, _dragOffsetY * 0.3),
                  child: GestureDetector(
                    onTap: _isRecording
                        ? () => _stopRecording(cancel: false)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isCancelled
                            ? Colors.red
                            : theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: theme.colorScheme.onPrimary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:social/utils/date_utils.dart';

class ViewImageScreen extends StatefulWidget {
  final String imageUrl;
  final String? caption;
  final bool isProfile;
  final String? senderName;
  final dynamic timestamp;

  const ViewImageScreen({
    super.key,
    required this.imageUrl,
    this.caption,
    this.isProfile = false,
    this.senderName,
    this.timestamp,
  });

  @override
  State<ViewImageScreen> createState() => _ViewImageScreenState();
}

class _ViewImageScreenState extends State<ViewImageScreen>
    with SingleTickerProviderStateMixin {
  bool _showBars = true;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    if (widget.timestamp != null) {
      if (widget.isProfile) {
      } else {
        // format time
        _timeString = DateUtil().formatMessageTime(widget.timestamp);
      }
    }
  }

  void _toggleBars() {
    setState(() {
      _showBars = !_showBars;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 0.3 opacity black
    final overlayColor = Colors.black.withValues(alpha: 0.3);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Interactive Image (Zoomable)
          GestureDetector(
            onTap: _toggleBars,
            child: Center(
              child: Hero(
                tag: widget.isProfile ? 'pfp' : widget.imageUrl,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4.0,
                  child: widget.imageUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error, color: Colors.white),
                        )
                      : Image.file(File(widget.imageUrl), fit: BoxFit.contain),
                ),
              ),
            ),
          ),

          // 2. Custom App Bar (Top Overlay)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showBars ? 1.0 : 0.0,
              child: Container(
                color: overlayColor,
                padding:
                    MediaQuery.of(context).padding +
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      if (widget.senderName != null) ...[
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.senderName!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (_timeString.isNotEmpty)
                              Text(
                                _timeString,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Caption (Bottom Overlay)
          if (widget.caption != null && widget.caption!.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showBars ? 1.0 : 0.0,
                child: Container(
                  color: overlayColor,
                  padding:
                      MediaQuery.of(context).padding.copyWith(top: 0) +
                      const EdgeInsets.all(16),
                  child: SafeArea(
                    top: false,
                    child: Text(
                      widget.caption!,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

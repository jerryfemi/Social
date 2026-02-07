import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class MediaGalleryPager extends StatefulWidget {
  final List<Map<String, dynamic>> mediaMessages;
  final int initialIndex;

  const MediaGalleryPager({
    super.key,
    required this.mediaMessages,
    required this.initialIndex,
  });

  @override
  State<MediaGalleryPager> createState() => _MediaGalleryPagerState();
}

class _MediaGalleryPagerState extends State<MediaGalleryPager> {
  late ExtendedPageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_currentIndex + 1} of ${widget.mediaMessages.length}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (widget.mediaMessages[_currentIndex]['senderName'] != null)
              Text(
                '${widget.mediaMessages[_currentIndex]['senderName'] ?? 'Unknown'} • ${_formatTimestamp(widget.mediaMessages[_currentIndex]['timestamp'])}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ExtendedImageGesturePageView.builder(
            physics: const BouncingScrollPhysics(),
            controller: _pageController,
            itemCount: widget.mediaMessages.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (BuildContext context, int index) {
              final message = widget.mediaMessages[index];
              final type = message['type'];
              final content = message['message'] as String;
              final localPath = message['localFilePath'] as String?;
              final String heroTag =
                  content; // Using content URL/Path as Hero tag

              // VIDEO PLACEHOLDER
              if (type == 'video') {
                return Hero(
                  tag: heroTag,
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            color: Colors.white,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              context.push(
                                '/videoPlayer',
                                extra: {
                                  'videoUrl': content,
                                  'caption': message['caption'],
                                },
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Tap to Play Video',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // IMAGE
              Widget imageWidget;
              if (localPath != null && localPath.isNotEmpty) {
                if (kIsWeb) {
                  imageWidget = ExtendedImage.network(
                    localPath,
                    fit: BoxFit.contain,
                    mode: ExtendedImageMode.gesture,
                    initGestureConfigHandler: (state) {
                      return GestureConfig(
                        minScale: 0.9,
                        animationMinScale: 0.7,
                        maxScale: 3.0,
                        animationMaxScale: 3.5,
                        speed: 1.0,
                        inertialSpeed: 100.0,
                        initialScale: 1.0,
                        inPageView: true,
                        initialAlignment: InitialAlignment.center,
                      );
                    },
                  );
                } else {
                  imageWidget = ExtendedImage.file(
                    File(localPath) as dynamic,
                    fit: BoxFit.contain,
                    mode: ExtendedImageMode.gesture,
                    initGestureConfigHandler: (state) {
                      return GestureConfig(
                        minScale: 0.9,
                        animationMinScale: 0.7,
                        maxScale: 3.0,
                        animationMaxScale: 3.5,
                        speed: 1.0,
                        inertialSpeed: 100.0,
                        initialScale: 1.0,
                        inPageView: true,
                        initialAlignment: InitialAlignment.center,
                      );
                    },
                  );
                }
              } else {
                imageWidget = ExtendedImage.network(
                  content,
                  fit: BoxFit.contain,
                  mode: ExtendedImageMode.gesture,
                  initGestureConfigHandler: (state) {
                    return GestureConfig(
                      minScale: 0.9,
                      animationMinScale: 0.7,
                      maxScale: 3.0,
                      animationMaxScale: 3.5,
                      speed: 1.0,
                      inertialSpeed: 100.0,
                      initialScale: 1.0,
                      inPageView: true,
                      initialAlignment: InitialAlignment.center,
                    );
                  },
                  loadStateChanged: (ExtendedImageState state) {
                    switch (state.extendedImageLoadState) {
                      case LoadState.loading:
                        return const Center(child: CircularProgressIndicator());
                      case LoadState.completed:
                        return state.completedWidget;
                      case LoadState.failed:
                        return const Center(
                          child: Icon(Icons.broken_image, color: Colors.white),
                        );
                    }
                  },
                );
              }

              return Hero(tag: heroTag, child: imageWidget);
            },
          ),

          // CAPTION & INDICATOR
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.mediaMessages[_currentIndex]['caption'] != null &&
                    widget.mediaMessages[_currentIndex]['caption'].isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.black54,
                    width: double.infinity,
                    child: Text(
                      widget.mediaMessages[_currentIndex]['caption'],
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 10),

                // Page Indicator
                if (widget.mediaMessages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: AnimatedSmoothIndicator(
                      activeIndex: _currentIndex,
                      count: widget.mediaMessages.length,
                      effect: const ScrollingDotsEffect(
                        activeDotColor: Colors.white,
                        dotColor: Colors.white24,
                        dotHeight: 8,
                        dotWidth: 8,
                      ),
                      onDotClicked: (index) {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    if (timestamp is Timestamp) {
      return DateFormat(' • MMM d, h:mm a').format(timestamp.toDate());
    }
    return '';
  }
}

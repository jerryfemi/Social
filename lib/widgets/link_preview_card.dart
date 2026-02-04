import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:social/services/link_preview_service.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isSender;

  const LinkPreviewCard({super.key, required this.url, required this.isSender});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  final _linkPreviewService = LinkPreviewService();

  Metadata? _metadata;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void didUpdateWidget(LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadMetadata();
    }
  }

  void _loadMetadata() {
    // Check cache first - if cached, show immediately (no loading state)
    final cached = _linkPreviewService.getCached(widget.url);
    if (cached != null) {
      setState(() {
        _metadata = cached.metadata;
        _hasError = cached.hasError;
        _isLoading = false;
      });
      return;
    }

    // Not cached - show loading and fetch
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    _linkPreviewService.getMetadata(widget.url).then((result) {
      if (mounted) {
        setState(() {
          _metadata = result.metadata;
          _hasError = result.hasError;
          _isLoading = false;
        });
      }
    });
  }

  void _launchUrl() async {
    final uri = Uri.parse(widget.url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ERROR STATE: Hide if error
    if (_hasError) {
      return const SizedBox.shrink();
    }

    final cardColor = widget.isSender
        ? Colors.black.withValues(alpha: 0.15)
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    final textColor = widget.isSender ? Colors.white : Colors.black;
    final subTextColor = widget.isSender ? Colors.white70 : Colors.black54;

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Skeletonizer(
          enabled: true,
          child: Container(
            width: 250,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (_metadata == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: _launchUrl,
        child: Container(
          width: 250,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSender ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_metadata!.image != null)
                CachedNetworkImage(
                  imageUrl: _metadata!.image!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_metadata!.title != null)
                      Text(
                        _metadata!.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                    if (_metadata!.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _metadata!.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      Uri.parse(widget.url).host.replaceFirst('www.', ''),
                      style: TextStyle(
                        fontSize: 10,
                        color: subTextColor.withValues(alpha: 0.7),
                      ),
                    ),
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

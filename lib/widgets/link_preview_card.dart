import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isSender;

  const LinkPreviewCard({super.key, required this.url, required this.isSender});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  Metadata? _metadata;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
  }

  @override
  void didUpdateWidget(LinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _fetchMetadata();
    }
  }

  Future<void> _fetchMetadata() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint("🔍 Fetching URL: ${widget.url}"); // DEBUG LOG

      final response = await http.get(
        Uri.parse(widget.url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
        },
      );

      debugPrint("📡 Status Code: ${response.statusCode}"); // DEBUG LOG

      if (response.statusCode == 200) {
        // 1. Convert response to Document
        final document = MetadataFetch.responseToDocument(response);

        // 2. Parse Metadata
        final data = MetadataParser.parse(document);
        data.url = widget.url;

        debugPrint("📄 Title found: ${data.title}"); // DEBUG LOG
        debugPrint("🖼️ Image found: ${data.image}"); // DEBUG LOG

        if (mounted) {
          setState(() {
            _metadata = data;
            _isLoading = false;
            if (data.title == null && data.image == null) {
              _errorMessage = "No Metadata Found";
            }
          });
        }
      } else {
        // Fallback for non-200 status
        if (mounted) {
          setState(() {
            _errorMessage = "HTTP Error: ${response.statusCode}";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ CRITICAL ERROR: $e"); // DEBUG LOG
      if (mounted) {
        setState(() {
          _errorMessage = "Exception: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _launchUrl() async {
    final uri = Uri.parse(widget.url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ERROR STATE: Show Red Box instead of hiding
    if (_errorMessage != null) {
      return SizedBox.shrink();
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

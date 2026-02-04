import 'package:flutter/foundation.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:http/http.dart' as http;

/// Cached result for a link preview
class LinkPreviewResult {
  final Metadata? metadata;
  final bool hasError;

  LinkPreviewResult({this.metadata, this.hasError = false});
}

/// Singleton service for fetching and caching link previews
class LinkPreviewService {
  // Singleton instance
  static final LinkPreviewService _instance = LinkPreviewService._internal();
  factory LinkPreviewService() => _instance;
  LinkPreviewService._internal();

  // In-memory cache: URL -> Result
  final Map<String, LinkPreviewResult> _cache = {};

  // Track in-progress requests to avoid duplicate fetches
  final Map<String, Future<LinkPreviewResult>> _inProgress = {};

  /// Check if a URL is already cached
  bool isCached(String url) => _cache.containsKey(url);

  /// Get cached result (returns null if not cached)
  LinkPreviewResult? getCached(String url) => _cache[url];

  /// Fetch metadata for a URL (uses cache if available)
  Future<LinkPreviewResult> getMetadata(String url) async {
    // 1. Return cached result if available
    if (_cache.containsKey(url)) {
      return _cache[url]!;
    }

    // 2. If already fetching this URL, wait for that request
    if (_inProgress.containsKey(url)) {
      return _inProgress[url]!;
    }

    // 3. Start new fetch and track it
    final future = _fetchMetadata(url);
    _inProgress[url] = future;

    try {
      final result = await future;
      _cache[url] = result;
      return result;
    } finally {
      _inProgress.remove(url);
    }
  }

  /// Internal fetch logic
  Future<LinkPreviewResult> _fetchMetadata(String url) async {
    try {
      debugPrint("🔍 Fetching URL: $url");

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
            },
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("📡 Status Code: ${response.statusCode}");

      if (response.statusCode == 200) {
        final document = MetadataFetch.responseToDocument(response);
        final data = MetadataParser.parse(document);
        data.url = url;

        debugPrint("📄 Title found: ${data.title}");
        debugPrint("🖼️ Image found: ${data.image}");

        // If no useful metadata, mark as error
        if (data.title == null && data.image == null) {
          return LinkPreviewResult(hasError: true);
        }

        return LinkPreviewResult(metadata: data);
      } else {
        return LinkPreviewResult(hasError: true);
      }
    } catch (e) {
      debugPrint("❌ Link preview error: $e");
      return LinkPreviewResult(hasError: true);
    }
  }

  /// Clear the cache (useful for testing or memory management)
  void clearCache() {
    _cache.clear();
  }

  /// Remove a specific URL from cache
  void removeFromCache(String url) {
    _cache.remove(url);
  }
}

import 'package:flutter/foundation.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

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

  // Hive Box name
  static const String _boxName = 'link_previews';
  Box? _box;

  // In-memory cache: URL -> Result (for faster access during session)
  final Map<String, LinkPreviewResult> _memoryCache = {};

  // Track in-progress requests to avoid duplicate fetches
  final Map<String, Future<LinkPreviewResult>> _inProgress = {};

  /// Initialize Hive box
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox(_boxName);
  }

  /// Check if a URL is already cached
  bool isCached(String url) {
    if (_memoryCache.containsKey(url)) return true;
    return _box?.containsKey(url) ?? false;
  }

  /// Get cached result (returns null if not cached)
  LinkPreviewResult? getCached(String url) {
    // 1. Check memory
    if (_memoryCache.containsKey(url)) {
      return _memoryCache[url];
    }

    // 2. Check Hive
    if (_box != null && _box!.containsKey(url)) {
      final data = _box!.get(url) as Map;
      final metadata = Metadata();
      metadata.title = data['title'];
      metadata.description = data['description'];
      metadata.image = data['image'];
      metadata.url = data['url'];

      final result = LinkPreviewResult(
        metadata: metadata,
        hasError: data['hasError'] ?? false,
      );

      // Populate memory cache
      _memoryCache[url] = result;
      return result;
    }

    return null;
  }

  /// Fetch metadata for a URL (uses cache if available)
  Future<LinkPreviewResult> getMetadata(String url) async {
    // Ensure initialized
    await init();

    // 1. Return cached result if available
    final cached = getCached(url);
    if (cached != null) return cached;

    // 2. If already fetching this URL, wait for that request
    if (_inProgress.containsKey(url)) {
      return _inProgress[url]!;
    }

    // 3. Start new fetch and track it
    final future = _fetchMetadata(url);
    _inProgress[url] = future;

    try {
      final result = await future;

      // Save to memory
      _memoryCache[url] = result;

      // Save to Hive
      if (_box != null) {
        await _box!.put(url, {
          'title': result.metadata?.title,
          'description': result.metadata?.description,
          'image': result.metadata?.image,
          'url': result.metadata?.url,
          'hasError': result.hasError,
        });
      }

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
  Future<void> clearCache() async {
    _memoryCache.clear();
    await _box?.clear();
  }

  /// Remove a specific URL from cache
  Future<void> removeFromCache(String url) async {
    _memoryCache.remove(url);
    await _box?.delete(url);
  }
}

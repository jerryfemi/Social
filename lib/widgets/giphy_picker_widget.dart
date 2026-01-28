import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:social/services/giphy_service.dart';

class GiphyPickerWidget extends StatefulWidget {
  final Function(String url) onGifSelected;
  final Function(String url)? onGifLongPress;
  final TextEditingController? searchController;

  const GiphyPickerWidget({
    super.key,
    required this.onGifSelected,
    this.onGifLongPress,
    this.searchController,
  });

  @override
  State<GiphyPickerWidget> createState() => _GiphyPickerWidgetState();
}

class _GiphyPickerWidgetState extends State<GiphyPickerWidget> {
  final _gifService = GiphyService();
  final _scrollController = ScrollController();

  List<String> _gifs = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _offset = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadGifs();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore) {
          _loadMore();
        }
      }
    });

    widget.searchController?.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    widget.searchController?.removeListener(_onSearchChanged);
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _loadGifs(reset: true),
    );
  }

  void _loadGifs({bool reset = false}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _gifs = [];
          _offset = 0;
        });
      }
    }

    final query = widget.searchController?.text.trim() ?? '';
    List<String> newGifs;

    try {
      if (query.isEmpty) {
        newGifs = await _gifService.fetchTrending(offset: _offset);
      } else {
        newGifs = await _gifService.search(query, offset: _offset);
      }

      if (mounted) {
        setState(() {
          _gifs = newGifs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint('Error loading GIFs: $e');
    }
  }

  // load more
  void _loadMore() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
      _offset += 20;
    });

    final query = widget.searchController?.text.trim() ?? '';
    List<String> moreGifs;

    try {
      if (query.isEmpty) {
        moreGifs = await _gifService.fetchTrending(offset: _offset);
      } else {
        moreGifs = await _gifService.search(query, offset: _offset);
      }

      if (mounted) {
        setState(() {
          _gifs.addAll(moreGifs);
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _gifs.isEmpty
              ? Center(child: Text('No GIFs found'))
              : GridView.builder(
                  controller: _scrollController,
                  padding: EdgeInsetsGeometry.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemBuilder: (context, index) {
                    final url = _gifs[index];

                    return GestureDetector(
                      onTap: () => widget.onGifSelected(url),
                      onLongPress: () => widget.onGifLongPress?.call(url),
                      child: Container(
                        color: Colors.grey[200],
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[300]),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error, color: Colors.red),
                          fadeInDuration: const Duration(milliseconds: 200),
                        ),
                      ),
                    );
                  },
                  itemCount: _gifs.length,
                ),
        ),
        if (_isLoadingMore)
          Padding(
            padding: EdgeInsetsGeometry.all(8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

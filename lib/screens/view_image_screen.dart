import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ViewImageScreen extends StatelessWidget {
  final String imageUrl;
  final String? caption;
  final bool isProfile;
  const ViewImageScreen({
    super.key,
    required this.imageUrl,
    this.caption,
    this.isProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Hero(
        tag: isProfile ? 'pfp' : imageUrl,
        child: Stack(
          children: [
            Positioned.fill(child: CachedNetworkImage(imageUrl: imageUrl)),
            if (caption != null)
              Positioned(
                bottom: 50,
                left: 20,
                child: Text(caption!, style: TextStyle(fontSize: 16)),
              ),
            Positioned(
              top: 50,
              left: 20,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

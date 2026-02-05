import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserTile extends StatelessWidget {
  final String text;
  final String? photourl;
  final Widget? subtitle;
  final Widget? trailing;
  final void Function()? onTap;
  final void Function()? onLongPress;
  final bool isGroup;
  const UserTile({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.text,
    this.photourl,
    this.subtitle,
    this.trailing,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: EdgeInsets.only(top: 3),
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(),
        child: Row(
          children: [
            // profile photo
            ClipOval(
              child: photourl != null && photourl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photourl!,
                      width: 66,
                      height: 66,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) => Icon(
                        isGroup ? Icons.group : Icons.person,
                        size: 30,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      radius: 33,
                      child: Icon(
                        isGroup ? Icons.group : Icons.person,
                        size: 30,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (subtitle != null) subtitle!,
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class MyTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final Widget? trailing;
  final void Function()? ontap;
  const MyTile({
    super.key,
    this.leading,
    required this.title,
    this.trailing,
    this.ontap,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: leading,
        title: Text(title),
        trailing: trailing,
        onTap: ontap,
      ),
    );
  }
}

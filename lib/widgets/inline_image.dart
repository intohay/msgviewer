import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';


class InlineImage extends StatefulWidget {
  final String imagePath;

  const InlineImage({Key? key, required this.imagePath}) : super(key: key);

  @override
  State<InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<InlineImage> {

  OverlayEntry? overlayEntry;

  void _showOverlay(BuildContext context, FileImage image) {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: Colors.black,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: PhotoView(
                  imageProvider: image,
                  backgroundDecoration: BoxDecoration(color: Colors.black)
                ),
              ),
              Positioned(
                top: 40,
                left: 10,
                child: IconButton(
                  icon: Icon(Icons.close, size: 30, color: Colors.white),
                  onPressed: () => overlayEntry?.remove(),
                )
              )
            ]
          )
        )
      )
    );
    Overlay.of(context).insert(overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
          onTap: () {
            _showOverlay(context, FileImage(File(widget.imagePath)));
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom:10.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 300,
              ),
              child: Image.file(
                File(widget.imagePath)
              ),
            ),
          ),
        );
  }
}

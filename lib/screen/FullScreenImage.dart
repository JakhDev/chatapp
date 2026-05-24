import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class FullScreenImage extends StatefulWidget {
  final List<String> imageUrls;  // ← barcha rasmlar
  final int          initialIndex; // ← boshlang'ich indeks

  const FullScreenImage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  late final PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);

    // Status bar ni yashirish
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    // Status bar ni qaytarish
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Gallery (swipe + double tap zoom) ──────────────────────────
          PhotoViewGallery.builder(
            pageController: _pageCtrl,
            itemCount:      widget.imageUrls.length,
            onPageChanged:  (i) => setState(() => _currentIndex = i),
            scrollPhysics:  const BouncingScrollPhysics(),
            builder: (_, i) => PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(widget.imageUrls[i]),

              // ✅ Standart holat — rasm ekranga sig'adigan bo'lsin
              initialScale: PhotoViewComputedScale.contained,
              minScale:     PhotoViewComputedScale.contained,
              maxScale:     PhotoViewComputedScale.covered * 3,

              // ✅ Ikki marta tez bosish — zoom
              onTapUp: (ctx, details, controllerValue) {
                // handled by PhotoView natively
              },
              heroAttributes: PhotoViewHeroAttributes(
                  tag: widget.imageUrls[i]),
            ),
            loadingBuilder: (_, event) => Center(
              child: CircularProgressIndicator(
                value: event == null
                    ? 0
                    : event.cumulativeBytesLoaded /
                    (event.expectedTotalBytes ?? 1),
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ),

          // ── Top bar ────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (widget.imageUrls.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.imageUrls.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
          ),

          // ── Bottom dots (agar bir nechta rasm) ────────────────────────
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) {
                  final selected = i == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width:  selected ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
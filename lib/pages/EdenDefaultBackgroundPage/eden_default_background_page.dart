import 'package:flutter/material.dart';

import '../../global/eden_gallery_player_globals.dart';

class EdenDefaultBackgroundOption {
  const EdenDefaultBackgroundOption({
    required this.path,
    required this.imageUrl,
  });

  final String path;
  final String imageUrl;

  String get displayName {
    final List<String> parts = path.split('/');
    if (parts.length >= 4) {
      return parts[3];
    }
    return path;
  }
}

class EdenDefaultBackgroundPage extends StatelessWidget {
  const EdenDefaultBackgroundPage({
    super.key,
    required this.options,
    required this.selectedPath,
  });

  final List<EdenDefaultBackgroundOption> options;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenGalleryPlayerGlobals.pageBackgroundColor,
      appBar: AppBar(
        backgroundColor: EdenGalleryPlayerGlobals.pageBackgroundColor,
        foregroundColor: Colors.white,
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop<String>(''),
            child: const Text(
              '清除',
              style: TextStyle(color: EdenGalleryPlayerGlobals.themeColor),
            ),
          ),
        ],
      ),
      body:
          options.isEmpty
              ? const Center(
                child: Text(
                  '没有可选背景',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              )
              : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final EdenDefaultBackgroundOption option = options[index];
                  return _BackgroundOptionTile(
                    option: option,
                    selected: option.path == selectedPath,
                    onTap: () => Navigator.of(context).pop<String>(option.path),
                  );
                },
              ),
    );
  }
}

class _BackgroundOptionTile extends StatelessWidget {
  const _BackgroundOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final EdenDefaultBackgroundOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC101823),
          border: Border.all(
            color:
                selected
                    ? EdenGalleryPlayerGlobals.themeColor
                    : const Color(0x33FFFFFF),
            width: selected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.network(
                option.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) {
                  return const ColoredBox(
                    color: Color(0xFF17212E),
                    child: Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white54,
                        size: 30,
                      ),
                    ),
                  );
                },
              ),
              // Align(
              //   alignment: Alignment.bottomCenter,
              //   child: DecoratedBox(
              //     decoration: const BoxDecoration(color: Color(0xB3000000)),
              //     child: SizedBox(
              //       width: double.infinity,
              //       child: Padding(
              //         padding: const EdgeInsets.symmetric(
              //           horizontal: 8,
              //           vertical: 7,
              //         ),
              //         child: Text(
              //           option.displayName,
              //           maxLines: 1,
              //           overflow: TextOverflow.ellipsis,
              //           textAlign: TextAlign.center,
              //           style: const TextStyle(
              //             color: Colors.white,
              //             fontSize: 13,
              //             fontWeight: FontWeight.w700,
              //           ),
              //         ),
              //       ),
              //     ),
              //   ),
              // ),
              if (selected)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: EdenGalleryPlayerGlobals.themeColor,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class EdenDefaultBackgroundPage extends StatefulWidget {
  const EdenDefaultBackgroundPage({
    super.key,
    required this.options,
    required this.selectedPath,
  });

  final List<EdenDefaultBackgroundOption> options;
  final String? selectedPath;

  @override
  State<EdenDefaultBackgroundPage> createState() =>
      _EdenDefaultBackgroundPageState();
}

class _EdenDefaultBackgroundPageState extends State<EdenDefaultBackgroundPage> {
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.selectedPath;
  }

  EdenDefaultBackgroundOption? get _selectedOption {
    final String? selectedPath = _selectedPath;
    if (selectedPath == null || selectedPath.isEmpty) {
      return null;
    }
    for (final EdenDefaultBackgroundOption option in widget.options) {
      if (option.path == selectedPath) {
        return option;
      }
    }
    return null;
  }

  void _toggleBackground(EdenDefaultBackgroundOption option) {
    setState(() {
      _selectedPath = _selectedPath == option.path ? null : option.path;
    });
  }

  void _commitAndPop() {
    Navigator.of(context).pop<String>(_selectedPath ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<String?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, String? result) {
        if (didPop) {
          return;
        }
        _commitAndPop();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          forceMaterialTransparency: true,
          foregroundColor: Colors.white,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _commitAndPop,
          ),
        ),
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: _BackgroundPreview(option: _selectedOption)),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x66000000),
                      Color(0x11000000),
                      Color(0xAA000000),
                    ],
                    stops: <double>[0, 0.52, 1],
                  ),
                ),
              ),
            ),
            if (widget.options.isEmpty)
              const Center(
                child: Text(
                  '没有可选背景',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              )
            else
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: SizedBox(
                      height: 112,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xA6080B12),
                          border: Border.all(color: const Color(0x26FFFFFF)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(10),
                          itemCount: widget.options.length,
                          separatorBuilder:
                              (BuildContext context, int index) =>
                                  const SizedBox(width: 10),
                          itemBuilder: (BuildContext context, int index) {
                            final EdenDefaultBackgroundOption option =
                                widget.options[index];
                            return SizedBox(
                              width: 118,
                              child: _BackgroundOptionTile(
                                option: option,
                                selected: option.path == _selectedPath,
                                onTap: () => _toggleBackground(option),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.option});

  final EdenDefaultBackgroundOption? option;

  @override
  Widget build(BuildContext context) {
    final EdenDefaultBackgroundOption? option = this.option;
    if (option == null) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(
      option.imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) {
        return const ColoredBox(color: Colors.black);
      },
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

part of '../character_gallery_page.dart';

class _CharacterGalleryScene extends StatefulWidget {
  const _CharacterGalleryScene({
    required this.characters,
    required this.selectedIndex,
    required this.selected,
    required this.onSelected,
  });

  final List<_CharacterEntry> characters;
  final int selectedIndex;
  final _CharacterEntry selected;
  final ValueChanged<int> onSelected;

  @override
  State<_CharacterGalleryScene> createState() => _CharacterGallerySceneState();
}

class _CharacterGallerySceneState extends State<_CharacterGalleryScene> {
  bool _isCharacterStripVisible = true;

  void _toggleCharacterStrip() {
    setState(() {
      _isCharacterStripVisible = !_isCharacterStripVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _CharacterStage(entry: widget.selected)),
        if (_isCharacterStripVisible)
          Positioned(
            left: viewPadding.left + 8.w,
            right: viewPadding.right + 8.w,
            bottom: viewPadding.bottom + 8.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: _CharacterStrip(
                    characters: widget.characters,
                    selectedIndex: widget.selectedIndex,
                    onSelected: widget.onSelected,
                  ),
                ),
                SizedBox(width: 6.w),
                _CharacterStripToggleButton(
                  isExpanded: true,
                  onTap: _toggleCharacterStrip,
                ),
              ],
            ),
          )
        else
          Positioned(
            right: viewPadding.right + 10.w,
            bottom: viewPadding.bottom + 10.h,
            child: _CharacterStripToggleButton(
              isExpanded: false,
              onTap: _toggleCharacterStrip,
            ),
          ),
      ],
    );
  }
}

class _CharacterStageBackground extends StatelessWidget {
  const _CharacterStageBackground({required this.backgroundPaths});

  final List<String> backgroundPaths;

  @override
  Widget build(BuildContext context) {
    final String? basePath =
        backgroundPaths.isEmpty ? null : backgroundPaths.first;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF080B12)),
      child:
          basePath == null
              ? const SizedBox.expand()
              : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    basePath,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    color: const Color(0x55080B12),
                    colorBlendMode: BlendMode.srcATop,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) {
                      return const SizedBox.expand();
                    },
                  ),
                  for (final String path in backgroundPaths)
                    Image.asset(
                      path,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return const SizedBox.expand();
                      },
                    ),
                ],
              ),
    );
  }
}

class _StageControlPanel extends StatelessWidget {
  const _StageControlPanel({
    required this.namePlate,
    required this.stageCount,
    required this.selectedStageIndex,
    required this.onStageSelected,
  });

  final Widget namePlate;
  final int stageCount;
  final int selectedStageIndex;
  final ValueChanged<int> onStageSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 146.w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          namePlate,
          SizedBox(height: 8.h),
          if (stageCount > 0)
            _StageVariantSelector(
              stageCount: stageCount,
              selectedStageIndex: selectedStageIndex,
              onStageSelected: onStageSelected,
            ),
        ],
      ),
    );
  }
}

class _StageVariantSelector extends StatelessWidget {
  const _StageVariantSelector({
    required this.stageCount,
    required this.selectedStageIndex,
    required this.onStageSelected,
  });

  final int stageCount;
  final int selectedStageIndex;
  final ValueChanged<int> onStageSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 210.h),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(stageCount, (int index) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == stageCount - 1 ? 0 : 5.h,
              ),
              child: _StageVariantButton(
                label: '立绘${index + 1}',
                isSelected: index == selectedStageIndex,
                onTap: () => onStageSelected(index),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StageVariantButton extends StatelessWidget {
  const _StageVariantButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color themeColor = CommonManager.instance.themeColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6.r),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 64.w,
          height: 24.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                isSelected
                    ? themeColor.withAlpha(230)
                    : const Color(0xB00B1018),
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color:
                  isSelected
                      ? Color.lerp(themeColor, Colors.white, 0.30)!
                      : const Color(0x33FFFFFF),
              width: isSelected ? 1.5.r : 1.r,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? const Color(0xFF14100A) : Colors.white,
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _CharacterStripToggleButton extends StatelessWidget {
  const _CharacterStripToggleButton({
    required this.isExpanded,
    required this.onTap,
  });

  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color themeColor = CommonManager.instance.themeColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8.r),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: isExpanded ? 28.w : 34.r,
          height: isExpanded ? _CharacterStripShell.height : 34.r,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB00B1018),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: isExpanded ? const Color(0x30FFFFFF) : themeColor,
              width: isExpanded ? 1.r : 1.5.r,
            ),
          ),
          child: Icon(
            isExpanded
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_up_rounded,
            color: isExpanded ? Colors.white : themeColor,
            size: 18.r,
          ),
        ),
      ),
    );
  }
}

class _CharacterStripShell extends StatelessWidget {
  const _CharacterStripShell({required this.child});

  static double get height => 82.h;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB00B1018),
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(color: const Color(0x30FFFFFF)),
      ),
      child: child,
    );
  }
}

class _CharacterTileShell extends StatelessWidget {
  const _CharacterTileShell({required this.isSelected, required this.child});

  final bool isSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color themeColor = CommonManager.instance.themeColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 58.w,
      decoration: BoxDecoration(
        color: const Color(0xFF121A24),
        borderRadius: BorderRadius.circular(7.r),
        border: Border.all(
          color: isSelected ? themeColor : const Color(0x33FFFFFF),
          width: isSelected ? 2.r : 1.r,
        ),
      ),
      child: child,
    );
  }
}

class _CharacterTileLabel extends StatelessWidget {
  const _CharacterTileLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 2.h),
      color: const Color(0xB0000000),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CharacterInfoCard extends StatelessWidget {
  const _CharacterInfoCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB00B1018),
        borderRadius: BorderRadius.circular(7.r),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xCCFFFFFF),
                fontSize: 8.sp,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

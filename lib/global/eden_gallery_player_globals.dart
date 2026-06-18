import 'package:flutter/material.dart';

enum EdenGallerySubtitleLanguage { chinese, japanese }

class EdenGalleryPlayerGlobals {
  const EdenGalleryPlayerGlobals._();

  static const Color defaultBgColor = Color(0xF5F5F5FF);
  static const Color themeColor = Color(0xFF9FA1FF);
  static const Color pageBackgroundColor = Color(0xFFFFE3E3);
  static const Color panelBackgroundColor = Color(0xD90B1018);
  static const Color panelBorderColor = Color(0x33FFFFFF);
  static const Color selectedTextColor = Color(0xFF15110A);

  static const EdenGallerySubtitleLanguage defaultSubtitleLanguage =
      EdenGallerySubtitleLanguage.chinese;
  static EdenGallerySubtitleLanguage subtitleLanguage = defaultSubtitleLanguage;
}

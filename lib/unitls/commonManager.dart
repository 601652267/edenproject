// ignore_for_file: file_names

import 'package:flutter/material.dart';

class CommonManager {
  CommonManager._();

  static final CommonManager instance = CommonManager._();

  final Color themeColor = const Color(0xFFFFD166);
  final List<Object> characterList = <Object>[];

  void setCharacterList(List<Object> characters) {
    characterList
      ..clear()
      ..addAll(characters);
  }
}

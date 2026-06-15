import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class EdenGalleryFavoritesStore {
  const EdenGalleryFavoritesStore._();

  static const MethodChannel _channel = MethodChannel(
    'edenproject/app_storage',
  );
  static const String _fileName = 'eden_gallery_favorites.json';

  static Future<Set<int>> loadFavoriteCardIds() async {
    final File file = await _favoritesFile();
    if (!await file.exists()) {
      return <int>{};
    }

    try {
      final String text = await file.readAsString();
      if (text.trim().isEmpty) {
        return <int>{};
      }

      final Object? decoded = jsonDecode(text);
      final Object? rawIds =
          decoded is Map<String, dynamic>
              ? decoded['favoriteCardIds']
              : decoded;
      if (rawIds is! List) {
        return <int>{};
      }

      return rawIds.map(_asInt).where((int id) => id > 0).toSet();
    } on FormatException {
      return <int>{};
    } on FileSystemException {
      return <int>{};
    }
  }

  static Future<void> saveFavoriteCardIds(Set<int> favoriteCardIds) async {
    final File file = await _favoritesFile();
    await file.parent.create(recursive: true);
    final List<int> sortedIds = favoriteCardIds.toList()..sort();
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(<String, Object>{'favoriteCardIds': sortedIds}),
      flush: true,
    );
  }

  static Future<File> _favoritesFile() async {
    final Directory directory = await _supportDirectory();
    return File('${directory.path}/$_fileName');
  }

  static Future<Directory> _supportDirectory() async {
    try {
      final String? path = await _channel.invokeMethod<String>(
        'getEdenGalleryStorageDirectory',
      );
      if (path != null && path.isNotEmpty) {
        return Directory(path);
      }
    } on MissingPluginException {
      // Flutter tests do not install the native storage channel.
    }

    return Directory('${Directory.systemTemp.path}/eden_gallery_player');
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

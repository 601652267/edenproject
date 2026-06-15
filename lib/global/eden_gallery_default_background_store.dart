import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class EdenGalleryDefaultBackgroundStore {
  const EdenGalleryDefaultBackgroundStore._();

  static const MethodChannel _channel = MethodChannel(
    'edenproject/app_storage',
  );
  static const String _fileName = 'eden_gallery_default_background.json';

  static Future<String?> loadDefaultBackgroundPath() async {
    final File file = await _defaultBackgroundFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final String text = await file.readAsString();
      if (text.trim().isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final String path = decoded['backgroundPath']?.toString().trim() ?? '';
      return path.isEmpty ? null : path;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> saveDefaultBackgroundPath(String? backgroundPath) async {
    final File file = await _defaultBackgroundFile();
    await file.parent.create(recursive: true);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(<String, Object?>{
        'backgroundPath':
            backgroundPath == null || backgroundPath.isEmpty
                ? null
                : backgroundPath,
      }),
      flush: true,
    );
  }

  static Future<File> _defaultBackgroundFile() async {
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
}

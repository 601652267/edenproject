import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';
// 348654518
// 592221588
// 864602675
import '../../unitls/commonManager.dart';

part 'subView/character_gallery_scene.dart';

class CharacterGalleryPage extends StatefulWidget {
  const CharacterGalleryPage({super.key});

  @override
  State<CharacterGalleryPage> createState() => _CharacterGalleryPageState();
}

class _CharacterGalleryPageState extends State<CharacterGalleryPage> {
  late final Future<List<_CharacterEntry>> _charactersFuture;
  int _selectedIndex = 0;
  bool _isCharacterLoadingShown = false;
  bool _reportedCharacterLoadError = false;

  @override
  void initState() {
    super.initState();
    _charactersFuture = _loadCharactersWithLoading();
  }

  @override
  void dispose() {
    _dismissCharacterLoading(immediate: true);
    super.dispose();
  }

  Future<List<_CharacterEntry>> _loadCharactersWithLoading() async {
    _showCharacterLoading();
    try {
      return await _loadCharacters();
    } finally {
      _dismissCharacterLoading();
    }
  }

  void _showCharacterLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _isCharacterLoadingShown = true;
      EasyLoading.show(status: '角色资源加载中...');
    });
  }

  void _dismissCharacterLoading({bool immediate = false}) {
    if (immediate) {
      if (_isCharacterLoadingShown) {
        _isCharacterLoadingShown = false;
        EasyLoading.dismiss();
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isCharacterLoadingShown) {
        return;
      }

      _isCharacterLoadingShown = false;
      EasyLoading.dismiss();
    });
  }

  void _reportCharacterLoadError() {
    if (_reportedCharacterLoadError) {
      return;
    }

    _reportedCharacterLoadError = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        EasyLoading.showError('角色资源加载失败');
      }
    });
  }

  Future<List<_CharacterEntry>> _loadCharacters() async {
    final List<Object> loaded = await Future.wait<Object>(<Future<Object>>[
      rootBundle.loadString('assets/file/character_info_manifest.json'),
      rootBundle.loadString('assets/file/character_assets_manifest.json'),
      rootBundle.loadString('AssetManifest.json'),
    ]);

    final Map<String, dynamic> characterManifest =
        jsonDecode(loaded[0] as String) as Map<String, dynamic>;
    final Map<String, dynamic> characterAssetsManifest =
        jsonDecode(loaded[1] as String) as Map<String, dynamic>;
    final Map<String, dynamic> assetManifest =
        jsonDecode(loaded[2] as String) as Map<String, dynamic>;
    final Map<String, dynamic> assetFolders =
        (characterAssetsManifest['folders'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final List<String> assetKeys = assetManifest.keys.toList()..sort();
    final Map<String, dynamic> cards =
        (characterManifest['cards'] as Map<String, dynamic>?) ??
        <String, dynamic>{};

    final List<_CharacterEntry> entries = <_CharacterEntry>[];
    for (final MapEntry<String, dynamic> cardEntry in cards.entries) {
      final int? cardId = int.tryParse(cardEntry.key);
      if (cardId == null || cardId < 11100001 || cardId > 11301006) {
        continue;
      }

      final Map<String, dynamic> card =
          (cardEntry.value as Map<String, dynamic>?) ?? <String, dynamic>{};
      final _CharacterEntry? entry = await _buildCharacterEntry(
        cardId: cardId,
        card: card,
        assetKeys: assetKeys,
        assetFolders: assetFolders,
      );
      if (entry != null) {
        entries.add(entry);
      }
    }

    entries.sort(
      (_CharacterEntry a, _CharacterEntry b) => a.cardId.compareTo(b.cardId),
    );
    CommonManager.instance.setCharacterList(entries);
    return entries;
  }

  Future<_CharacterEntry?> _buildCharacterEntry({
    required int cardId,
    required Map<String, dynamic> card,
    required List<String> assetKeys,
    required Map<String, dynamic> assetFolders,
  }) async {
    final String cardIdText = cardId.toString();
    final List<String> relatedFolders = _relatedFolders(cardIdText, assetKeys);
    if (relatedFolders.isEmpty) {
      return null;
    }

    final Map<String, String> stageSkins = _stageSkins(card);
    final List<_StageAsset> stages = await _stageCandidates(
      cardIdText,
      relatedFolders,
      assetKeys,
      assetFolders,
      stageSkins,
    );
    if (stages.isEmpty) {
      return null;
    }

    return _CharacterEntry(
      cardId: cardId,
      name: _stringValue(card['name']) ?? cardIdText,
      nameCn: _stringValue(card['nameCn']) ?? _stringValue(card['name']),
      stages: stages,
      backgroundPath: _pickBackground(relatedFolders, assetKeys),
      portraitPath: _pickPortrait(cardIdText, relatedFolders, assetKeys),
    );
  }

  Future<List<_StageAsset>> _stageCandidates(
    String cardIdText,
    List<String> folders,
    List<String> assetKeys,
    Map<String, dynamic> assetFolders,
    Map<String, String> stageSkins,
  ) async {
    final List<_StageAsset> candidates = <_StageAsset>[];
    for (final String folder in folders) {
      candidates.addAll(
        await _stageAssetsForFolder(
          folder,
          assetKeys,
          assetFolders,
          stageSkins,
        ),
      );
    }

    if (candidates.isEmpty) {
      return <_StageAsset>[];
    }

    candidates.sort((_StageAsset a, _StageAsset b) {
      final double aScore = _stageFolderScore(a, cardIdText);
      final double bScore = _stageFolderScore(b, cardIdText);
      final int scoreCompare = aScore.compareTo(bScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.stageKey.compareTo(b.stageKey);
    });

    return candidates;
  }

  double _stageFolderScore(_StageAsset stage, String cardIdText) {
    final int skeletonBytes = stage.skeletonBytes;
    double score = 0;
    if (skeletonBytes < 30000) {
      score += 100;
    }

    if (stage.atlasRegionCount < 4) {
      score += 100;
    } else if (stage.atlasRegionCount < 12) {
      score += 10;
    }

    score += stage.folder == cardIdText ? -8 : 8;

    score += _spineFilePenalty(stage.stageName);
    score += _variantStagePenalty(stage.folder, cardIdText);
    score -= (skeletonBytes / 50000).clamp(0, 4);
    return score;
  }

  double _spineFilePenalty(String stageName) {
    final String lower = stageName.toLowerCase();
    if (lower.endsWith('_b') || lower.endsWith('_bg')) {
      return 120;
    }
    if (lower.endsWith('_qj') || lower.endsWith('_scene')) {
      return 120;
    }
    if (lower.endsWith('_q')) {
      return 14;
    }
    if (lower.endsWith('_r')) {
      return -8;
    }
    return 0;
  }

  double _variantStagePenalty(String folder, String cardIdText) {
    if (folder == cardIdText) {
      return 0;
    }

    final String suffix = folder.substring(cardIdText.length);
    if (suffix == '_3' || suffix == '_4' || suffix == '_1') {
      return 0;
    }
    if (suffix == '_3_1') {
      return 0;
    }
    if (RegExp(r'^_3_[2-9]').hasMatch(suffix)) {
      return 5;
    }
    return 1;
  }

  Future<List<_StageAsset>> _stageAssetsForFolder(
    String folder,
    List<String> assetKeys,
    Map<String, dynamic> assetFolders,
    Map<String, String> stageSkins,
  ) async {
    final List<String> atlasPaths = _assetsIn(
      assetKeys,
      folder,
      'spine',
      (String path) => path.endsWith('.atlas.prefab'),
    );
    final List<String> skeletonPaths = _assetsIn(
      assetKeys,
      folder,
      'spine',
      (String path) => path.endsWith('.skel.prefab'),
    );
    final List<String> texturePaths =
        <String>{
          ..._assetsIn(
            assetKeys,
            folder,
            'texture',
            (String path) => path.toLowerCase().endsWith('.png'),
          ),
          ..._assetsIn(
            assetKeys,
            folder,
            'background',
            (String path) => path.toLowerCase().endsWith('.png'),
          ),
        }.toList();
    if (atlasPaths.isEmpty || skeletonPaths.isEmpty || texturePaths.isEmpty) {
      return <_StageAsset>[];
    }

    final Map<String, String> skeletonsByName = <String, String>{
      for (final String skeletonPath in skeletonPaths)
        _spineAssetName(skeletonPath, '.skel.prefab'): skeletonPath,
    };
    final Map<String, _StageLayerAsset> layersByName =
        <String, _StageLayerAsset>{};

    for (final String atlasPath in atlasPaths) {
      final String stageName = _spineAssetName(atlasPath, '.atlas.prefab');
      final String? skeletonPath = skeletonsByName[stageName];
      if (skeletonPath == null) {
        continue;
      }

      final String atlasSource = await rootBundle.loadString(atlasPath);
      final int skeletonBytes = _assetBytes(folder, skeletonPath, assetFolders);
      final int atlasRegionCount = _atlasRegionCount(atlasSource);
      layersByName[stageName] = _StageLayerAsset(
        stageName: stageName,
        atlasPath: atlasPath,
        skeletonPath: skeletonPath,
        texturePaths: texturePaths,
        skeletonBytes: skeletonBytes,
        atlasRegionCount: atlasRegionCount,
        isRoleLayer:
            !_looksLikeEffectOnlyStage(
              stageName: stageName,
              skeletonBytes: skeletonBytes,
              atlasRegionCount: atlasRegionCount,
            ),
        skinName: stageSkins[_normalizeStageName(stageName)],
      );
    }

    if (layersByName.isEmpty) {
      return <_StageAsset>[];
    }

    final List<_StageLayerAsset> layers =
        layersByName.values.toList()..sort(_compareStageLayers);
    final bool hasRoleLayer = layers.any(_isLikelyRoleLayer);
    if (!hasRoleLayer) {
      return <_StageAsset>[];
    }

    return <_StageAsset>[
      _StageAsset(
        folder: folder,
        stageName: _mergedStageName(folder, layers),
        layers: layers,
        backgroundPaths: await _pickStageBackgrounds(
          folder,
          assetKeys,
          assetFolders,
        ),
      ),
    ];
  }

  String _mergedStageName(String folder, List<_StageLayerAsset> layers) {
    final String normalizedFolder = folder.replaceAll('CardShowSpine_', '');
    final _StageLayerAsset primary = layers.reduce(
      (_StageLayerAsset a, _StageLayerAsset b) =>
          _roleLayerScore(a, normalizedFolder) >=
                  _roleLayerScore(b, normalizedFolder)
              ? a
              : b,
    );
    return primary.stageName;
  }

  int _compareStageLayers(_StageLayerAsset a, _StageLayerAsset b) {
    final int aPriority = _stageLayerDrawPriority(a);
    final int bPriority = _stageLayerDrawPriority(b);
    final int priorityCompare = aPriority.compareTo(bPriority);
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    final int roleCompare = _roleLayerScore(
      a,
      '',
    ).compareTo(_roleLayerScore(b, ''));
    if (roleCompare != 0) {
      return roleCompare;
    }

    final int orderCompare = _stageLayerSuffixOrder(
      a.stageName,
    ).compareTo(_stageLayerSuffixOrder(b.stageName));
    if (orderCompare != 0) {
      return orderCompare;
    }

    return a.stageName.compareTo(b.stageName);
  }

  int _stageLayerDrawPriority(_StageLayerAsset layer) {
    final String lower = layer.stageName.toLowerCase();
    if (lower.endsWith('_b') ||
        lower.endsWith('_bg') ||
        lower.contains('_bg_') ||
        lower.endsWith('_qj')) {
      return 0;
    }
    if (lower.endsWith('_q') || lower.endsWith('_fish')) {
      return 1;
    }
    if (_isLikelyRoleLayer(layer)) {
      return 3;
    }
    return 2;
  }

  int _stageLayerSuffixOrder(String stageName) {
    final String lower = stageName.toLowerCase();
    if (lower.endsWith('_b')) {
      return 0;
    }
    if (lower.endsWith('_q')) {
      return 1;
    }
    if (lower.endsWith('_r')) {
      return 9;
    }
    final RegExpMatch? numberedLayerMatch = RegExp(
      r'_(\d+)$',
    ).firstMatch(stageName);
    if (numberedLayerMatch != null) {
      return int.tryParse(numberedLayerMatch.group(1) ?? '') ?? 1;
    }
    return 1;
  }

  bool _isLikelyRoleLayer(_StageLayerAsset layer) {
    return layer.isRoleLayer;
  }

  int _roleLayerScore(_StageLayerAsset layer, String folderHint) {
    int score = layer.atlasRegionCount * 1000 + layer.skeletonBytes ~/ 100;
    final String lower = layer.stageName.toLowerCase();
    if (lower.endsWith('_r')) {
      score += 200000;
    }
    if (folderHint.isNotEmpty && lower.endsWith(folderHint.toLowerCase())) {
      score += 30000;
    }
    if (lower.endsWith('_b') ||
        lower.endsWith('_q') ||
        lower.endsWith('_bg') ||
        lower.endsWith('_qj') ||
        lower.contains('_bg_')) {
      score -= 200000;
    }
    return score;
  }

  bool _looksLikeEffectOnlyStage({
    required String stageName,
    required int skeletonBytes,
    required int atlasRegionCount,
  }) {
    final String lower = stageName.toLowerCase();
    if (lower.endsWith('_b') || lower.endsWith('_bg')) {
      return true;
    }
    if (lower.endsWith('_qj') || lower.endsWith('_scene')) {
      return true;
    }

    return skeletonBytes < 60000 && atlasRegionCount <= 4;
  }

  Map<String, String> _stageSkins(Map<String, dynamic> card) {
    final List<dynamic> fashions =
        card['fashions'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, String> stageSkins = <String, String>{};

    for (final dynamic fashion in fashions) {
      final Map<String, dynamic>? fashionData =
          fashion as Map<String, dynamic>?;
      if (fashionData == null) {
        continue;
      }

      final String? showSpine = _stringValue(fashionData['showSpine']);
      final String? showSpineType = _stringValue(fashionData['showSpineType']);
      if (showSpine == null || showSpineType == null || showSpineType == '0') {
        continue;
      }

      stageSkins[_normalizeStageName(showSpine)] = showSpineType;
    }

    return stageSkins;
  }

  int _assetBytes(
    String folder,
    String assetPath,
    Map<String, dynamic> assetFolders,
  ) {
    final Map<String, dynamic>? folderData =
        assetFolders[folder] as Map<String, dynamic>?;
    final List<dynamic> files =
        folderData?['files'] as List<dynamic>? ?? <dynamic>[];
    final String assetFileName = _basename(assetPath);
    for (final dynamic file in files) {
      final Map<String, dynamic>? fileData = file as Map<String, dynamic>?;
      if (fileData == null) {
        continue;
      }
      final String? manifestFile = _stringValue(fileData['file']);
      final String relativeAssetPath = assetPath.replaceFirst(
        'assets/file/',
        '',
      );
      if (fileData['type'] == 'spine' &&
          (manifestFile == assetFileName ||
              manifestFile == relativeAssetPath ||
              manifestFile == assetPath)) {
        return (fileData['bytes'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  List<String> _relatedFolders(String cardIdText, List<String> assetKeys) {
    final Set<String> folders = <String>{};
    final RegExp folderPattern = RegExp(
      '^assets/file/(${RegExp.escape(cardIdText)}(?:_[^/]+)?)/',
    );

    for (final String assetKey in assetKeys) {
      final RegExpMatch? match = folderPattern.firstMatch(assetKey);
      if (match != null) {
        final String folder = match.group(1)!;
        if (_isDisplayVariantFolder(folder, cardIdText)) {
          folders.add(folder);
        }
      }
    }

    final List<String> sortedFolders = folders.toList()..sort();
    return sortedFolders;
  }

  bool _isDisplayVariantFolder(String folder, String cardIdText) {
    if (folder == cardIdText) {
      return true;
    }

    final String suffix = folder.substring(cardIdText.length);
    if (RegExp(r'^_0\d+$').hasMatch(suffix)) {
      return false;
    }
    return RegExp(r'^_[1-9]\d*$').hasMatch(suffix);
  }

  String? _pickBackground(List<String> folders, List<String> assetKeys) {
    final List<String> backgrounds = <String>[];
    for (final String folder in folders) {
      backgrounds.addAll(
        _assetsIn(
          assetKeys,
          folder,
          'background',
          (String path) => path.toLowerCase().endsWith('.png'),
        ),
      );
      backgrounds.addAll(
        _assetsIn(assetKeys, folder, 'texture', (String path) {
          final String fileName = _basename(path).toLowerCase();
          return fileName.endsWith('.png') &&
              (fileName.contains('bg') || fileName.endsWith('_back.png'));
        }),
      );
    }

    if (backgrounds.isEmpty) {
      return null;
    }

    backgrounds.sort((String a, String b) {
      final int aScore = _backgroundScore(a);
      final int bScore = _backgroundScore(b);
      final int scoreCompare = aScore.compareTo(bScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.compareTo(b);
    });
    return backgrounds.first;
  }

  Future<List<String>> _pickStageBackgrounds(
    String folder,
    List<String> assetKeys,
    Map<String, dynamic> assetFolders,
  ) async {
    final List<String> searchFolders = <String>[
      folder,
      if (_parentVariantFolder(folder) case final String parentFolder)
        parentFolder,
    ];
    final List<String> backgroundImages = <String>[];
    for (final String searchFolder in searchFolders) {
      backgroundImages.addAll(
        _assetsIn(
          assetKeys,
          searchFolder,
          'background',
          (String path) =>
              path.toLowerCase().endsWith('.png') &&
              !_isGeneratedSpriteBackground(path),
        ),
      );
    }

    final List<String> backgrounds =
        backgroundImages.isNotEmpty ? backgroundImages : <String>[];
    if (backgrounds.isEmpty) {
      for (final String searchFolder in searchFolders) {
        backgrounds.addAll(
          _assetsIn(assetKeys, searchFolder, 'texture', (String path) {
            final String fileName = _basename(path).toLowerCase();
            return fileName.endsWith('.png') &&
                (fileName.contains('bg') || fileName.endsWith('_back.png')) &&
                !_isGeneratedSpriteBackground(path);
          }),
        );
      }
    }

    if (backgrounds.isEmpty) {
      return <String>[];
    }

    backgrounds.sort((String a, String b) {
      final int aScore = _backgroundScore(a);
      final int bScore = _backgroundScore(b);
      final int scoreCompare = aScore.compareTo(bScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final int byteCompare = _assetManifestBytes(
        b,
        assetFolders,
      ).compareTo(_assetManifestBytes(a, assetFolders));
      if (byteCompare != 0) {
        return byteCompare;
      }
      return a.compareTo(b);
    });
    final List<String> unique = _uniqueBackgrounds(backgrounds);
    if (unique.length <= 1) {
      return unique;
    }

    final _PngSize? baseSize = await _readPngSize(unique.first);
    if (baseSize == null) {
      return unique;
    }

    final List<String> filtered = <String>[unique.first];
    for (final String path in unique.skip(1)) {
      final _PngSize? overlaySize = await _readPngSize(path);
      if (overlaySize == null ||
          _shouldKeepSceneOverlay(baseSize, overlaySize)) {
        filtered.add(path);
      }
    }
    return filtered;
  }

  bool _shouldKeepSceneOverlay(_PngSize base, _PngSize overlay) {
    final double widthRatio = overlay.width / base.width;
    final double heightRatio = overlay.height / base.height;
    return widthRatio >= 0.55 && heightRatio >= 0.55;
  }

  Future<_PngSize?> _readPngSize(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      if (data.lengthInBytes < 24) {
        return null;
      }

      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      const List<int> pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      for (int index = 0; index < pngSignature.length; index++) {
        if (bytes[index] != pngSignature[index]) {
          return null;
        }
      }

      final ByteData header = ByteData.sublistView(bytes, 16, 24);
      final int width = header.getUint32(0, Endian.big);
      final int height = header.getUint32(4, Endian.big);
      if (width <= 0 || height <= 0) {
        return null;
      }
      return _PngSize(width: width.toDouble(), height: height.toDouble());
    } catch (_) {
      return null;
    }
  }

  bool _isGeneratedSpriteBackground(String path) {
    final String lower = _basename(path).toLowerCase();
    return lower.contains('__sprite') ||
        lower.contains('__texture2d') ||
        lower.contains('__');
  }

  List<String> _uniqueBackgrounds(List<String> backgrounds) {
    final Set<String> seen = <String>{};
    final List<String> unique = <String>[];
    for (final String background in backgrounds) {
      final String key = _backgroundDedupeKey(background);
      if (seen.add(key)) {
        unique.add(background);
      }
    }
    return unique;
  }

  String _backgroundDedupeKey(String path) {
    return _basename(path)
        .toLowerCase()
        .replaceAll(RegExp(r' #\d+(?=\.png$)'), '')
        .replaceAll(RegExp(r'__[a-f0-9]+(?=\.png$)'), '')
        .replaceAll('__sprite', '');
  }

  String? _parentVariantFolder(String folder) {
    final RegExpMatch? match = RegExp(r'^(\d+_\d+)_\d+$').firstMatch(folder);
    return match?.group(1);
  }

  int _backgroundScore(String path) {
    final String lower = path.toLowerCase();
    int score = 0;
    if (lower.contains('/background/')) {
      score -= 20;
    }
    if (lower.endsWith('_back.png')) {
      score -= 10;
    }
    if (lower.contains('__sprite') || lower.contains('__texture2d')) {
      score += 50;
    }
    if (lower.contains('_mask')) {
      score += 50;
    }
    if (path.contains('#')) {
      score += 10;
    }
    if (!lower.contains('bg')) {
      score += 20;
    }
    return score;
  }

  int _assetManifestBytes(String assetPath, Map<String, dynamic> assetFolders) {
    final String? folder = _folderFromAssetPath(assetPath);
    if (folder == null) {
      return 0;
    }
    final Map<String, dynamic>? folderData =
        assetFolders[folder] as Map<String, dynamic>?;
    final List<dynamic> files =
        folderData?['files'] as List<dynamic>? ?? <dynamic>[];
    final String relativeAssetPath = assetPath.replaceFirst('assets/file/', '');
    final String assetFileName = _basename(assetPath);

    for (final dynamic file in files) {
      final Map<String, dynamic>? fileData = file as Map<String, dynamic>?;
      if (fileData == null) {
        continue;
      }
      final String? manifestFile = _stringValue(fileData['file']);
      if (manifestFile == assetFileName ||
          (manifestFile != null && _basename(manifestFile) == assetFileName) ||
          manifestFile == relativeAssetPath ||
          manifestFile == assetPath) {
        return (fileData['bytes'] as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  String? _folderFromAssetPath(String assetPath) {
    final List<String> parts = assetPath.split('/');
    if (parts.length < 3 || parts[0] != 'assets' || parts[1] != 'file') {
      return null;
    }
    return parts[2];
  }

  String? _pickPortrait(
    String cardIdText,
    List<String> relatedFolders,
    List<String> assetKeys,
  ) {
    final List<String> preferredFolders = <String>[
      cardIdText,
      ...relatedFolders.where((String folder) => folder != cardIdText),
    ];
    final List<String> portraits = <String>[];
    for (final String folder in preferredFolders) {
      portraits.addAll(
        _assetsIn(
          assetKeys,
          folder,
          'portrait',
          (String path) => path.toLowerCase().endsWith('.png'),
        ),
      );
    }

    if (portraits.isEmpty) {
      return null;
    }

    portraits.sort((String a, String b) {
      final int aScore = _portraitScore(a);
      final int bScore = _portraitScore(b);
      final int scoreCompare = aScore.compareTo(bScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.compareTo(b);
    });
    return portraits.first;
  }

  int _portraitScore(String path) {
    final String lower = path.toLowerCase();
    if (lower.contains('_1.png')) {
      return 0;
    }
    if (lower.contains('_2.png')) {
      return 1;
    }
    return 2;
  }

  List<String> _assetsIn(
    List<String> assetKeys,
    String folder,
    String subfolder,
    bool Function(String path) test,
  ) {
    final String prefix = 'assets/file/$folder/$subfolder/';
    return assetKeys
        .where((String path) => path.startsWith(prefix) && test(path))
        .toList()
      ..sort();
  }

  int _atlasRegionCount(String atlasSource) {
    final List<String> lines = const LineSplitter().convert(atlasSource);
    int count = 0;
    for (int index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isEmpty || line.contains(':')) {
        continue;
      }
      final String nextLine = _nextNonEmptyLine(lines, index + 1);
      if (nextLine.startsWith('rotate:')) {
        count += 1;
      }
    }
    return count;
  }

  String _nextNonEmptyLine(List<String> lines, int startIndex) {
    for (int index = startIndex; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isNotEmpty) {
        return line;
      }
    }
    return '';
  }

  String _spineAssetName(String path, String suffix) {
    final String name = _basename(path);
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
    return name;
  }

  String _normalizeStageName(String value) {
    return value.toLowerCase();
  }

  String _basename(String path) {
    final List<String> parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: FutureBuilder<List<_CharacterEntry>>(
        future: _charactersFuture,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<_CharacterEntry>> snapshot,
        ) {
          if (snapshot.hasError) {
            _reportCharacterLoadError();
            return _MessageView(message: snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return const SizedBox.expand();
          }

          final List<_CharacterEntry> loadedCharacters = snapshot.data!;
          final List<_CharacterEntry> globalCharacters = CommonManager
              .instance
              .characterList
              .whereType<_CharacterEntry>()
              .toList(growable: false);
          final List<_CharacterEntry> characters =
              globalCharacters.isEmpty ? loadedCharacters : globalCharacters;
          if (characters.isEmpty) {
            return const _MessageView(message: '没有找到可展示的角色资源');
          }

          final int safeIndex = _selectedIndex.clamp(0, characters.length - 1);
          final _CharacterEntry selected = characters[safeIndex];
          return _CharacterGalleryScene(
            characters: characters,
            selectedIndex: safeIndex,
            selected: selected,
            onSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          );
        },
      ),
    );
  }
}

class _CharacterStage extends StatefulWidget {
  const _CharacterStage({required this.entry});

  final _CharacterEntry entry;

  @override
  State<_CharacterStage> createState() => _CharacterStageState();
}

class _CharacterStageState extends State<_CharacterStage> {
  int _stageIndex = 0;
  bool _showFallback = false;
  final Set<String> _failedStageKeys = <String>{};

  _CharacterEntry get entry => widget.entry;

  _StageAsset get stage =>
      entry.stages[_stageIndex.clamp(0, entry.stages.length - 1)];

  @override
  void didUpdateWidget(covariant _CharacterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.cardId != widget.entry.cardId) {
      _stageIndex = 0;
      _showFallback = false;
      _failedStageKeys.clear();
    }
  }

  void _handleStageFailed() {
    if (!mounted || _showFallback) {
      return;
    }

    final String failedStageKey = stage.stageKey;
    setState(() {
      _failedStageKeys.add(failedStageKey);
      _showFallback = true;
    });
  }

  void _handleStageSelected(int index) {
    if (_stageIndex == index) {
      if (_showFallback) {
        setState(() {
          _failedStageKeys.remove(stage.stageKey);
          _showFallback = false;
        });
      }
      return;
    }

    setState(() {
      _stageIndex = index;
      _showFallback = _failedStageKeys.contains(stage.stageKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: _CharacterStageBackground(
            backgroundPaths: stage.backgroundPaths,
          ),
        ),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size viewportSize = Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
              );

              return _showFallback
                  ? _StageFallback(entry: entry, stage: stage)
                  : _SpinePlayer(
                    key: ValueKey<String>(stage.stageKey),
                    entry: entry,
                    stage: stage,
                    viewportSize: viewportSize,
                    onFailed: _handleStageFailed,
                  );
            },
          ),
        ),
        Positioned(
          left: viewPadding.left + 14.w,
          top: viewPadding.top + 10.h,
          child: _StageControlPanel(
            namePlate: _CharacterNamePlate(entry: entry, stage: stage),
            stageCount: entry.stages.length,
            selectedStageIndex: _stageIndex,
            onStageSelected: _handleStageSelected,
          ),
        ),
      ],
    );
  }
}

class _SpinePlayer extends StatefulWidget {
  const _SpinePlayer({
    super.key,
    required this.entry,
    required this.stage,
    required this.viewportSize,
    required this.onFailed,
  });

  final _CharacterEntry entry;
  final _StageAsset stage;
  final Size viewportSize;
  final VoidCallback onFailed;

  @override
  State<_SpinePlayer> createState() => _SpinePlayerState();
}

class _SpinePlayerState extends State<_SpinePlayer> {
  static const String _spineRuntimeAsset = 'assets/spine_player/spine-ts.js';

  late Future<WebViewController> _controllerFuture;
  String? _error;
  bool _reportedFailure = false;
  bool _isSpineLoadingShown = false;

  @override
  void initState() {
    super.initState();
    _controllerFuture = _createControllerWithLoading();
  }

  @override
  void didUpdateWidget(covariant _SpinePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage.stageKey != widget.stage.stageKey ||
        _hasViewportSizeChanged(oldWidget.viewportSize, widget.viewportSize)) {
      setState(() {
        _error = null;
        _reportedFailure = false;
        _controllerFuture = _createControllerWithLoading();
      });
    }
  }

  @override
  void dispose() {
    _dismissSpineLoading(immediate: true);
    super.dispose();
  }

  bool _hasViewportSizeChanged(Size oldSize, Size newSize) {
    return (oldSize.width - newSize.width).abs() > 1 ||
        (oldSize.height - newSize.height).abs() > 1;
  }

  Future<WebViewController> _createControllerWithLoading() async {
    _showSpineLoading();
    try {
      return await _createController();
    } catch (_) {
      _dismissSpineLoading();
      rethrow;
    }
  }

  void _showSpineLoading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _isSpineLoadingShown = true;
      EasyLoading.show(status: '立绘加载中...');
    });
  }

  void _dismissSpineLoading({bool immediate = false}) {
    if (immediate) {
      if (_isSpineLoadingShown) {
        _isSpineLoadingShown = false;
        EasyLoading.dismiss();
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSpineLoadingShown) {
        return;
      }

      _isSpineLoadingShown = false;
      EasyLoading.dismiss();
    });
  }

  Future<WebViewController> _createController() async {
    final String html = await _buildPlayerHtml(
      widget.stage,
      widget.viewportSize,
    );
    final WebViewController controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent)
          ..addJavaScriptChannel(
            'SpineBridge',
            onMessageReceived: (JavaScriptMessage message) {
              if (!mounted) {
                return;
              }

              final String value = message.message;
              if (value == 'ready') {
                _dismissSpineLoading();
                setState(() {
                  _error = null;
                });
              } else if (value.startsWith('error:')) {
                _dismissSpineLoading();
                setState(() {
                  _error = value.substring('error:'.length);
                });
                if (!_reportedFailure) {
                  _reportedFailure = true;
                  widget.onFailed();
                }
              }
            },
          );

    await controller.loadHtmlString(html);
    return controller;
  }

  Future<String> _buildPlayerHtml(_StageAsset stage, Size viewportSize) async {
    final String spineRuntimeSource = _escapeScript(
      await rootBundle.loadString(_spineRuntimeAsset),
    );
    final List<Map<String, Object?>> layerPayloads = <Map<String, Object?>>[];
    for (final _StageLayerAsset layer in stage.layers) {
      final String atlasSource = await rootBundle.loadString(layer.atlasPath);
      final ByteData skeletonData = await rootBundle.load(layer.skeletonPath);
      final Uint8List skeletonBytes = skeletonData.buffer.asUint8List(
        skeletonData.offsetInBytes,
        skeletonData.lengthInBytes,
      );

      final List<String> atlasPageNames = _atlasPageNames(atlasSource);
      final Map<String, String> texturePaths = _selectTexturePaths(
        atlasPageNames,
        layer.texturePaths,
      );
      final Map<String, String> textures = <String, String>{};
      for (final MapEntry<String, String> textureEntry
          in texturePaths.entries) {
        final ByteData textureData = await rootBundle.load(textureEntry.value);
        final Uint8List textureBytes = textureData.buffer.asUint8List(
          textureData.offsetInBytes,
          textureData.lengthInBytes,
        );
        textures[textureEntry.key] = base64Encode(textureBytes);
      }

      layerPayloads.add(<String, Object?>{
        'atlas': atlasSource,
        'skeleton': base64Encode(skeletonBytes),
        'textures': textures,
        'meta': <String, Object?>{
          'stageName': layer.stageName,
          'atlasRegionCount': layer.atlasRegionCount,
          'skeletonBytes': layer.skeletonBytes,
          'isRoleLayer': layer.isRoleLayer,
          'skinName': layer.skinName,
        },
      });
    }

    final String layersJson = jsonEncode(layerPayloads);
    final String flutterViewportJson = jsonEncode(<String, double>{
      'width': viewportSize.width,
      'height': viewportSize.height,
    });
    final String stageMetaJson = jsonEncode(<String, Object?>{
      'atlasRegionCount': stage.atlasRegionCount,
      'skeletonBytes': stage.skeletonBytes,
      'allowSceneSized': stage.allowSceneSized,
    });

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta id="spineViewport" name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.1, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body, #stage {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: transparent;
    }

    canvas {
      display: block;
      width: 100%;
      height: 100%;
      touch-action: none;
      background: transparent;
    }
  </style>
</head>
<body>
  <canvas id="stage"></canvas>
  <script>$spineRuntimeSource</script>
  <script>
    const spineAsset = {
      layers: $layersJson,
      flutterViewport: $flutterViewportJson,
      meta: $stageMetaJson
    };
    const maxCanvasPixelRatio = 2;
    const viewportScaleMin = 0.1;
    const viewportScaleMax = 1.0;
    const visibleWidthRatio = 1.02;
    const visibleHeightRatio = 0.92;

    function postToFlutter(message) {
      if (window.SpineBridge && window.SpineBridge.postMessage) {
        window.SpineBridge.postMessage(message);
      }
    }

    window.onerror = function(message, source, lineno, colno, error) {
      postToFlutter('error:' + (error && error.stack ? error.stack : message));
    };

    function base64ToUint8Array(base64) {
      const binary = atob(base64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return bytes;
    }

    function loadImage(base64) {
      return new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = reject;
        image.src = 'data:image/png;base64,' + base64;
      });
    }

    function clamp(value, min, max) {
      return Math.max(min, Math.min(max, value));
    }

    function currentViewportSize() {
      const flutterViewport = spineAsset.flutterViewport || {};
      const flutterWidth = Number(flutterViewport.width || 0);
      const flutterHeight = Number(flutterViewport.height || 0);
      if (flutterWidth > 0 && flutterHeight > 0) {
        return {
          width: flutterWidth,
          height: flutterHeight
        };
      }

      const visualViewport = window.visualViewport;
      const visualScale = visualViewport && visualViewport.scale ? visualViewport.scale : 1;
      const visualWidth = visualViewport && visualViewport.width ? visualViewport.width * visualScale : 0;
      const visualHeight = visualViewport && visualViewport.height ? visualViewport.height * visualScale : 0;

      return {
        width: Math.max(
          window.innerWidth || 0,
          document.documentElement.clientWidth || 0,
          visualWidth,
          1
        ),
        height: Math.max(
          window.innerHeight || 0,
          document.documentElement.clientHeight || 0,
          visualHeight,
          1
        )
      };
    }

    function calculateViewportScale(bounds) {
      const viewport = currentViewportSize();
      const targetWidth = viewport.width * visibleWidthRatio;
      const targetHeight = viewport.height * visibleHeightRatio;
      const widthScale = targetWidth / Math.max(bounds.width, 1);
      const heightScale = targetHeight / Math.max(bounds.height, 1);
      return clamp(Math.min(widthScale, heightScale), viewportScaleMin, viewportScaleMax);
    }

    function applyViewportScale(bounds) {
      const scale = calculateViewportScale(bounds);
      const viewport = document.getElementById('spineViewport');
      if (viewport) {
        viewport.setAttribute(
          'content',
          'width=device-width, initial-scale=' + scale.toFixed(4) +
            ', minimum-scale=' + viewportScaleMin.toFixed(4) +
            ', maximum-scale=1.0, user-scalable=no'
        );
      }

      return new Promise((resolve) => {
        window.requestAnimationFrame(() => {
          window.requestAnimationFrame(resolve);
        });
      });
    }

    async function loadTextures(gl, textureSources) {
      const textures = {};
      const sizes = {};
      for (const name of Object.keys(textureSources)) {
        const image = await loadImage(textureSources[name]);
        const texture = new spine.webgl.GLTexture(gl, image, false);
        texture.setFilters(gl.LINEAR, gl.LINEAR);
        texture.setWraps(gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE);
        textures[name] = texture;
        sizes[name] = {
          width: Math.max(image.naturalWidth || image.width || 1, 1),
          height: Math.max(image.naturalHeight || image.height || 1, 1)
        };
      }
      return { textures, sizes };
    }

    function normalizePageName(path) {
      return String(path || '').split('/').pop();
    }

    function insetAtlasRegionUvs(atlas, pageSizes) {
      atlas.regions.forEach((region) => {
        const pageName = normalizePageName(region.page && region.page.name);
        const pageSize = pageSizes[pageName] || {
          width: region.page && region.page.width ? region.page.width : 1,
          height: region.page && region.page.height ? region.page.height : 1
        };
        const halfTexelU = 0.5 / Math.max(pageSize.width, 1);
        const halfTexelV = 0.5 / Math.max(pageSize.height, 1);
        const minU = Math.min(region.u, region.u2);
        const maxU = Math.max(region.u, region.u2);
        const minV = Math.min(region.v, region.v2);
        const maxV = Math.max(region.v, region.v2);
        const insetU = Math.min(halfTexelU, Math.max((maxU - minU) * 0.25, 0));
        const insetV = Math.min(halfTexelV, Math.max((maxV - minV) * 0.25, 0));
        const uAscending = region.u <= region.u2;
        const vAscending = region.v <= region.v2;

        region.u = uAscending ? minU + insetU : maxU - insetU;
        region.u2 = uAscending ? maxU - insetU : minU + insetU;
        region.v = vAscending ? minV + insetV : maxV - insetV;
        region.v2 = vAscending ? maxV - insetV : minV + insetV;
      });
    }

    async function boot() {
      const canvas = document.getElementById('stage');
      const gl = canvas.getContext('webgl', {
        alpha: true,
        antialias: true,
        premultipliedAlpha: false
      }) || canvas.getContext('experimental-webgl', {
        alpha: true,
        antialias: true,
        premultipliedAlpha: false
      });

      if (!gl) {
        throw new Error('当前 WebView 不支持 WebGL，无法播放 Spine 动画。');
      }

      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);

      const renderer = new spine.webgl.SceneRenderer(canvas, gl, true);
      const runtimes = [];
      const defaultPreferredNames = [
        'idle',
        'renwu',
        'role',
        'r',
        'animation',
        'stand',
        'wait',
      ];

      function animationPreferences(layerAsset) {
        const meta = layerAsset.meta || {};
        const stageName = String(meta.stageName || '').toLowerCase();
        const names = [];
        if (stageName.endsWith('_b')) {
          names.push('h', 'h2', 'h3', 'bg', 'background');
        }
        if (stageName.endsWith('_q')) {
          names.push('q', 'q2', 'q3');
        }
        if (stageName.endsWith('_r')) {
          names.push('r', 'r2', 'r3', 'r4');
        }
        if (stageName.endsWith('_bg') || stageName.endsWith('_qj')) {
          names.push('idle', 'animation', 'shui', 'shell', 'niao1');
        }
        return names.concat(defaultPreferredNames);
      }

      for (const layerAsset of spineAsset.layers || []) {
        const loadedTextures = await loadTextures(gl, layerAsset.textures || {});
        const atlas = new spine.TextureAtlas(layerAsset.atlas, (path) => {
          const pageName = normalizePageName(path);
          const texture = loadedTextures.textures[pageName];
          if (!texture) {
            throw new Error('缺少纹理: ' + pageName);
          }
          return texture;
        });
        insetAtlasRegionUvs(atlas, loadedTextures.sizes);

        const atlasLoader = new spine.AtlasAttachmentLoader(atlas);
        const binary = new spine.SkeletonBinary(atlasLoader);
        const skeletonData = binary.readSkeletonData(base64ToUint8Array(layerAsset.skeleton));
        const layerMeta = layerAsset.meta || {};
        const requestedSkin = String(layerMeta.skinName || '');
        const hasRequestedSkin =
          requestedSkin.length > 0 &&
          skeletonData.skins.some((skin) => skin.name === requestedSkin);
        const skeleton = new spine.Skeleton(skeletonData);
        const stateData = new spine.AnimationStateData(skeletonData);
        const state = new spine.AnimationState(stateData);
        const runtime = {
          skeletonData,
          skeleton,
          stateData,
          state,
          requestedSkin,
          hasRequestedSkin,
          isRoleLayer: Boolean(layerMeta.isRoleLayer),
          animation: ''
        };

        resetSkeletonPose(runtime, skeleton);
        skeleton.updateWorldTransform();

        const animationNames = skeletonData.animations.map((animation) => animation.name);
        const preferredNames = animationPreferences(layerAsset);
        let animation = animationNames[0] || '';
        for (const name of preferredNames) {
          if (animationNames.indexOf(name) >= 0) {
            animation = name;
            break;
          }
        }
        runtime.animation = animation;
        if (animation) {
          state.setAnimation(0, animation, true);
          state.update(0);
          state.apply(skeleton);
          skeleton.updateWorldTransform();
        }

        runtimes.push(runtime);
      }

      if (!runtimes.length) {
        throw new Error('当前 Spine 没有可播放图层，尝试下一个资源。');
      }

      const fitBounds = computeAnimationBounds();
      await applyViewportScale(fitBounds);
      let lastFrameTime = performance.now() / 1000;
      let lastWidth = 0;
      let lastHeight = 0;

      function resetSkeletonPose(runtime, targetSkeleton) {
        if (runtime.hasRequestedSkin) {
          targetSkeleton.setSkinByName(runtime.requestedSkin);
        }
        targetSkeleton.setToSetupPose();
        if (runtime.hasRequestedSkin) {
          targetSkeleton.setSlotsToSetupPose();
        }
      }

      function computeAnimationBounds() {
        const fallback = { x: 0, y: 0, width: 1, height: 1 };
        const sampleOffset = new spine.Vector2();
        const sampleSize = new spine.Vector2();
        const sampleTemp = [];
        let minX = Number.POSITIVE_INFINITY;
        let minY = Number.POSITIVE_INFINITY;
        let maxX = Number.NEGATIVE_INFINITY;
        let maxY = Number.NEGATIVE_INFINITY;
        let valid = false;

        function addBounds(targetSkeleton) {
          targetSkeleton.getBounds(sampleOffset, sampleSize, sampleTemp);
          if (!isFinite(sampleSize.x) || !isFinite(sampleSize.y) || sampleSize.x <= 0 || sampleSize.y <= 0) {
            return;
          }
          minX = Math.min(minX, sampleOffset.x);
          minY = Math.min(minY, sampleOffset.y);
          maxX = Math.max(maxX, sampleOffset.x + sampleSize.x);
          maxY = Math.max(maxY, sampleOffset.y + sampleSize.y);
          valid = true;
        }

        const fitRuntimes = runtimes.some((runtime) => runtime.isRoleLayer)
          ? runtimes.filter((runtime) => runtime.isRoleLayer)
          : runtimes;

        for (const runtime of fitRuntimes) {
          if (runtime.animation) {
            const sampleAnimation = runtime.skeletonData.animations.find((item) => item.name === runtime.animation);
            const duration = Math.max(sampleAnimation && sampleAnimation.duration ? sampleAnimation.duration : 1, 0.1);
            const sampleCount = 10;
            const sampleSkeleton = new spine.Skeleton(runtime.skeletonData);
            const sampleState = new spine.AnimationState(runtime.stateData);
            sampleState.setAnimation(0, runtime.animation, true);
            for (let index = 0; index <= sampleCount; index++) {
              if (index > 0) {
                sampleState.update(duration / sampleCount);
              }
              resetSkeletonPose(runtime, sampleSkeleton);
              sampleState.apply(sampleSkeleton);
              sampleSkeleton.updateWorldTransform();
              addBounds(sampleSkeleton);
            }
          } else {
            addBounds(runtime.skeleton);
          }
        }

        if (!valid) {
          throw new Error('当前 Spine 没有可见边界，尝试下一个资源。');
        }

        return {
          x: minX,
          y: minY,
          width: Math.max(maxX - minX, 1),
          height: Math.max(maxY - minY, 1)
        };
      }

      function resize() {
        const ratio = Math.min(window.devicePixelRatio || 1, maxCanvasPixelRatio);
        const cssWidth = Math.max(canvas.clientWidth, 1);
        const cssHeight = Math.max(canvas.clientHeight, 1);
        const width = Math.max(Math.floor(cssWidth * ratio), 1);
        const height = Math.max(Math.floor(cssHeight * ratio), 1);
        if (canvas.width === width && canvas.height === height && lastWidth === cssWidth && lastHeight === cssHeight) {
          return false;
        }

        canvas.width = width;
        canvas.height = height;
        gl.viewport(0, 0, width, height);
        renderer.camera.setViewport(cssWidth, cssHeight);
        renderer.camera.update();
        lastWidth = cssWidth;
        lastHeight = cssHeight;
        return true;
      }

      function fitSkeleton() {
        const safeWidth = Math.max(fitBounds.width, 1);
        const safeHeight = Math.max(fitBounds.height, 1);
        const scale = 1;
        const targetCenterX = 0;
        const targetCenterY = 0;

        for (const runtime of runtimes) {
          const skeleton = runtime.skeleton;
          skeleton.x = 0;
          skeleton.y = 0;
          skeleton.scaleX = 1;
          skeleton.scaleY = 1;
          resetSkeletonPose(runtime, skeleton);
          if (runtime.animation) {
            runtime.state.apply(skeleton);
          }
          skeleton.updateWorldTransform();

          skeleton.scaleX = scale;
          skeleton.scaleY = scale;
          skeleton.x = targetCenterX - (fitBounds.x + safeWidth * 0.5) * scale;
          skeleton.y = targetCenterY - (fitBounds.y + safeHeight * 0.5) * scale;
          skeleton.updateWorldTransform();
        }
      }

      function render(frameTimeMs) {
        if (resize()) {
          fitSkeleton();
        }

        const frameTime = frameTimeMs / 1000;
        const delta = Math.min(Math.max(frameTime - lastFrameTime, 0), 0.064);
        lastFrameTime = frameTime;

        for (const runtime of runtimes) {
          runtime.state.update(delta);
          runtime.state.apply(runtime.skeleton);
          runtime.skeleton.updateWorldTransform();
        }

        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        renderer.begin();
        for (const runtime of runtimes) {
          renderer.drawSkeleton(runtime.skeleton, true);
        }
        renderer.end();
        window.requestAnimationFrame(render);
      }

      resize();
      fitSkeleton();
      postToFlutter('ready');
      window.requestAnimationFrame(render);
    }

    boot().catch((error) => {
      postToFlutter('error:' + (error && error.stack ? error.stack : error));
    });
  </script>
</body>
</html>
''';
  }

  List<String> _atlasPageNames(String atlasSource) {
    final List<String> names = <String>[];
    final List<String> lines = const LineSplitter().convert(atlasSource);
    for (int index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (!line.toLowerCase().endsWith('.png')) {
        continue;
      }
      final String nextLine = _nextNonEmptyLine(lines, index + 1);
      if (nextLine.startsWith('size:')) {
        names.add(_basename(line));
      }
    }
    return names;
  }

  String _nextNonEmptyLine(List<String> lines, int startIndex) {
    for (int index = startIndex; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isNotEmpty) {
        return line;
      }
    }
    return '';
  }

  Map<String, String> _selectTexturePaths(
    List<String> pageNames,
    List<String> texturePaths,
  ) {
    final Map<String, String> byName = <String, String>{
      for (final String path in texturePaths) _basename(path): path,
    };
    final List<String> pages =
        pageNames.isNotEmpty ? pageNames : byName.keys.toList();
    final Map<String, String> selected = <String, String>{};

    for (final String pageName in pages) {
      final String normalized = _basename(pageName);
      final String? exact = byName[normalized];
      if (exact != null) {
        selected[normalized] = exact;
        continue;
      }

      final String lowerName = normalized.toLowerCase();
      for (final MapEntry<String, String> entry in byName.entries) {
        if (entry.key.toLowerCase() == lowerName) {
          selected[normalized] = entry.value;
          break;
        }
      }
    }

    if (selected.isEmpty && texturePaths.isNotEmpty) {
      final String firstPath = texturePaths.first;
      selected[_basename(firstPath)] = firstPath;
    }

    return selected;
  }

  String _basename(String path) {
    final List<String> parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _escapeScript(String source) {
    return source.replaceAll('</script>', '<\\/script>');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WebViewController>(
      future: _controllerFuture,
      builder: (
        BuildContext context,
        AsyncSnapshot<WebViewController> snapshot,
      ) {
        if (snapshot.hasError) {
          return _MessageView(message: snapshot.error.toString());
        }

        return Stack(
          children: <Widget>[
            if (_error == null && snapshot.hasData)
              Positioned.fill(child: WebViewWidget(controller: snapshot.data!)),
          ],
        );
      },
    );
  }
}

class _StageFallback extends StatelessWidget {
  const _StageFallback({required this.entry, required this.stage});

  final _CharacterEntry entry;
  final _StageAsset stage;

  @override
  Widget build(BuildContext context) {
    final String? imagePath = entry.portraitPath ?? stage.fallbackImagePath;
    if (imagePath == null) {
      return _TileFallback(character: entry);
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 24.h),
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain,
          errorBuilder: (
            BuildContext context,
            Object error,
            StackTrace? stackTrace,
          ) {
            return _TileFallback(character: entry);
          },
        ),
      ),
    );
  }
}

class _CharacterStrip extends StatelessWidget {
  const _CharacterStrip({
    required this.characters,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_CharacterEntry> characters;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return _CharacterStripShell(
      child: SizedBox(
        height: _CharacterStripShell.height,
        child: ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          scrollDirection: Axis.horizontal,
          itemBuilder: (BuildContext context, int index) {
            final _CharacterEntry character = characters[index];
            return _CharacterTile(
              character: character,
              isSelected: index == selectedIndex,
              onTap: () => onSelected(index),
            );
          },
          separatorBuilder: (BuildContext context, int index) {
            return SizedBox(width: 6.w);
          },
          itemCount: characters.length,
        ),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.isSelected,
    required this.onTap,
  });

  final _CharacterEntry character;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: character.displayName,
      child: InkWell(
        borderRadius: BorderRadius.circular(7.r),
        onTap: onTap,
        child: _CharacterTileShell(
          isSelected: isSelected,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (character.portraitPath != null)
                  Image.asset(
                    character.portraitPath!,
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                    errorBuilder: (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) {
                      return _TileFallback(character: character);
                    },
                  )
                else
                  _TileFallback(character: character),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _CharacterTileLabel(text: character.displayName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileFallback extends StatelessWidget {
  const _TileFallback({required this.character});

  final _CharacterEntry character;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF17212E),
      child: Center(
        child: Text(
          character.cardId.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8.sp, letterSpacing: 0),
        ),
      ),
    );
  }
}

class _CharacterNamePlate extends StatelessWidget {
  const _CharacterNamePlate({required this.entry, required this.stage});

  final _CharacterEntry entry;
  final _StageAsset stage;

  @override
  Widget build(BuildContext context) {
    return _CharacterInfoCard(
      title: entry.displayName,
      subtitle: '${entry.cardId}  ${stage.folder}',
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.r),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.sp, letterSpacing: 0),
        ),
      ),
    );
  }
}

class _CharacterEntry {
  const _CharacterEntry({
    required this.cardId,
    required this.name,
    required this.nameCn,
    required this.stages,
    required this.backgroundPath,
    required this.portraitPath,
  });

  final int cardId;
  final String name;
  final String? nameCn;
  final List<_StageAsset> stages;
  final String? backgroundPath;
  final String? portraitPath;

  String get displayName => nameCn == null || nameCn!.isEmpty ? name : nameCn!;
}

class _StageAsset {
  const _StageAsset({
    required this.folder,
    required this.stageName,
    required this.layers,
    required this.backgroundPaths,
  });

  final String folder;
  final String stageName;
  final List<_StageLayerAsset> layers;
  final List<String> backgroundPaths;

  String? get backgroundPath =>
      backgroundPaths.isEmpty ? null : backgroundPaths.first;

  int get skeletonBytes => layers.fold<int>(
    0,
    (int value, _StageLayerAsset layer) => value + layer.skeletonBytes,
  );

  int get atlasRegionCount => layers.fold<int>(
    0,
    (int value, _StageLayerAsset layer) => value + layer.atlasRegionCount,
  );

  String get stageKey =>
      '$folder|${layers.map((_StageLayerAsset layer) => layer.layerKey).join('|')}';

  bool get allowSceneSized => backgroundPaths.isNotEmpty;

  String? get fallbackImagePath {
    for (final _StageLayerAsset layer in layers) {
      final String? imagePath = layer.fallbackImagePath;
      if (imagePath != null) {
        return imagePath;
      }
    }
    return null;
  }
}

class _PngSize {
  const _PngSize({required this.width, required this.height});

  final double width;
  final double height;
}

class _StageLayerAsset {
  const _StageLayerAsset({
    required this.stageName,
    required this.atlasPath,
    required this.skeletonPath,
    required this.texturePaths,
    required this.skeletonBytes,
    required this.atlasRegionCount,
    required this.isRoleLayer,
    required this.skinName,
  });

  final String stageName;
  final String atlasPath;
  final String skeletonPath;
  final List<String> texturePaths;
  final int skeletonBytes;
  final int atlasRegionCount;
  final bool isRoleLayer;
  final String? skinName;

  String get layerKey => '$atlasPath|$skeletonPath|${skinName ?? ''}';

  String? get fallbackImagePath {
    if (texturePaths.isEmpty) {
      return null;
    }

    final List<String> candidates =
        texturePaths.where((String path) {
          final String fileName = path.split('/').last.toLowerCase();
          return !fileName.endsWith('_bg.png') && !fileName.contains('bg_');
        }).toList();

    return candidates.isEmpty ? texturePaths.first : candidates.first;
  }
}

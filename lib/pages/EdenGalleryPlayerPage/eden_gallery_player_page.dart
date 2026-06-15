import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EdenGalleryPlayerOptions {
  const EdenGalleryPlayerOptions({
    this.config = const <String, Object?>{},
    this.cardId,
    this.characterIndex,
    this.stageIndex,
    this.stageNo,
    this.folder,
    this.stageKey,
    this.stageName,
    this.showStatus,
  });
  final Map<String, Object?> config;
  final Object? cardId;
  final int? characterIndex;
  final int? stageIndex;
  final int? stageNo;
  final String? folder;
  final String? stageKey;
  final String? stageName;
  final bool? showStatus;

  Map<String, Object?> toJson() {
    final Map<String, Object?> result = <String, Object?>{...config};
    void put(String key, Object? value) {
      if (value == null) {
        return;
      }
      if (value is String && value.isEmpty) {
        return;
      }
      result[key] = value;
    }

    put('cardId', cardId);
    put('characterIndex', characterIndex);
    put('stageIndex', stageIndex);
    put('stageNo', stageNo);
    put('folder', folder);
    put('stageKey', stageKey);
    put('stageName', stageName);
    put('showStatus', showStatus);
    return result;
  }

  String get signature => jsonEncode(toJson());
}

class EdenGalleryPlayerEvent {
  const EdenGalleryPlayerEvent({
    required this.type,
    required this.payload,
    required this.requestId,
    required this.rawMessage,
  });

  final String type;
  final Map<String, Object?> payload;
  final String requestId;
  final String rawMessage;

  String? get message {
    final Object? value = payload['message'];
    return value?.toString();
  }

  factory EdenGalleryPlayerEvent.fromMessage(String message) {
    try {
      final Object? decoded = jsonDecode(message);
      if (decoded is Map) {
        return EdenGalleryPlayerEvent(
          type: (decoded['type'] ?? '').toString(),
          payload: _asMap(decoded['payload']),
          requestId: (decoded['requestId'] ?? '').toString(),
          rawMessage: message,
        );
      }
    } catch (_) {
      // Keep raw messages visible for debugging bridge issues.
    }

    return EdenGalleryPlayerEvent(
      type: 'message',
      payload: <String, Object?>{'message': message},
      requestId: '',
      rawMessage: message,
    );
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return value.map<String, Object?>(
      (dynamic key, dynamic item) =>
          MapEntry<String, Object?>(key.toString(), item as Object?),
    );
  }
}

class EdenGalleryPlayerPage extends StatefulWidget {
  const EdenGalleryPlayerPage({
    super.key,
    this.options = const EdenGalleryPlayerOptions(),
  });

  final EdenGalleryPlayerOptions options;

  @override
  State<EdenGalleryPlayerPage> createState() => _EdenGalleryPlayerPageState();
}

class _EdenGalleryPlayerPageState extends State<EdenGalleryPlayerPage> {
  static const String _manifestAsset =
      'assets/gallery_player/gallery-assets/manifest.json';

  late final Future<List<_GalleryCharacter>> _charactersFuture;
  int _selectedCharacterIndex = 0;
  int _selectedStageIndex = 0;
  bool _selectionResolved = false;

  @override
  void initState() {
    super.initState();
    _charactersFuture = _loadCharacters();
  }

  Future<List<_GalleryCharacter>> _loadCharacters() async {
    final String text = await rootBundle.loadString(_manifestAsset);
    final Map<String, dynamic> manifest =
        jsonDecode(text) as Map<String, dynamic>;
    final List<dynamic> rawCharacters =
        manifest['characters'] as List<dynamic>? ?? <dynamic>[];
    return rawCharacters
        .whereType<Map<String, dynamic>>()
        .map(_GalleryCharacter.fromJson)
        .where((_GalleryCharacter character) => character.stages.isNotEmpty)
        .toList(growable: false);
  }

  void _resolveInitialSelection(List<_GalleryCharacter> characters) {
    if (_selectionResolved || characters.isEmpty) {
      return;
    }

    final Map<String, Object?> config = widget.options.toJson();
    int characterIndex = _intValue(config['characterIndex']) ?? 0;
    int stageIndex =
        _intValue(config['stageIndex']) ??
        ((_intValue(config['stageNo']) ?? 1) - 1);

    final String? requestedCardId = _stringValue(config['cardId']);
    final String? requestedFolder = _stringValue(config['folder']);
    final String? requestedStageKey = _stringValue(config['stageKey']);
    final String? requestedStageName = _stringValue(config['stageName']);

    for (int index = 0; index < characters.length; index += 1) {
      final _GalleryCharacter character = characters[index];
      final bool cardMatched =
          requestedCardId != null &&
          character.cardId.toString() == requestedCardId;
      final int matchedStageIndex = character.stages.indexWhere(
        (_GalleryStage stage) =>
            (requestedFolder != null && stage.folder == requestedFolder) ||
            (requestedStageKey != null &&
                stage.stageKey == requestedStageKey) ||
            (requestedStageName != null &&
                stage.stageName == requestedStageName),
      );

      if (cardMatched || matchedStageIndex >= 0) {
        characterIndex = index;
        if (matchedStageIndex >= 0) {
          stageIndex = matchedStageIndex;
        }
        break;
      }
    }

    _selectedCharacterIndex = characterIndex.clamp(0, characters.length - 1);
    _selectedStageIndex = stageIndex.clamp(
      0,
      characters[_selectedCharacterIndex].stages.length - 1,
    );
    _selectionResolved = true;
  }

  void _selectCharacter(List<_GalleryCharacter> characters, int index) {
    final int safeIndex = index.clamp(0, characters.length - 1);
    setState(() {
      _selectedCharacterIndex = safeIndex;
      _selectedStageIndex = 0;
    });
  }

  void _selectStage(_GalleryCharacter character, int index) {
    final int safeIndex = index.clamp(0, character.stages.length - 1);
    setState(() {
      _selectedStageIndex = safeIndex;
    });
  }

  EdenGalleryPlayerOptions _optionsFor(
    _GalleryCharacter character,
    int stageIndex,
  ) {
    return EdenGalleryPlayerOptions(
      config: widget.options.config,
      cardId: character.cardId,
      stageIndex: stageIndex,
      showStatus: widget.options.showStatus,
    );
  }

  @override
  void didUpdateWidget(covariant EdenGalleryPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.signature != widget.options.signature) {
      _selectionResolved = false;
      _charactersFuture.then((List<_GalleryCharacter> characters) {
        if (!mounted) {
          return;
        }
        setState(() {
          _resolveInitialSelection(characters);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: FutureBuilder<List<_GalleryCharacter>>(
        future: _charactersFuture,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<_GalleryCharacter>> snapshot,
        ) {
          if (snapshot.hasError) {
            return _GalleryMessage(message: '角色资源加载失败\n${snapshot.error}');
          }

          if (!snapshot.hasData) {
            return const _GalleryMessage(message: '角色资源加载中...');
          }

          final List<_GalleryCharacter> characters = snapshot.data!;
          if (characters.isEmpty) {
            return const _GalleryMessage(message: '没有找到可展示的角色资源');
          }

          _resolveInitialSelection(characters);
          final int safeCharacterIndex = _selectedCharacterIndex.clamp(
            0,
            characters.length - 1,
          );
          final _GalleryCharacter selected = characters[safeCharacterIndex];
          final int safeStageIndex = _selectedStageIndex.clamp(
            0,
            selected.stages.length - 1,
          );
          final _GalleryStage selectedStage = selected.stages[safeStageIndex];

          return _GalleryPlayerScaffold(
            player: EdenGalleryPlayerView(
              options: _optionsFor(selected, safeStageIndex),
            ),
            characters: characters,
            selectedCharacterIndex: safeCharacterIndex,
            selectedStageIndex: safeStageIndex,
            selected: selected,
            selectedStage: selectedStage,
            onCharacterSelected: (int index) {
              _selectCharacter(characters, index);
            },
            onStageSelected: (int index) {
              _selectStage(selected, index);
            },
          );
        },
      ),
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString();
    return text.isEmpty ? null : text;
  }
}

class _GalleryPlayerScaffold extends StatefulWidget {
  const _GalleryPlayerScaffold({
    required this.player,
    required this.characters,
    required this.selectedCharacterIndex,
    required this.selectedStageIndex,
    required this.selected,
    required this.selectedStage,
    required this.onCharacterSelected,
    required this.onStageSelected,
  });

  final Widget player;
  final List<_GalleryCharacter> characters;
  final int selectedCharacterIndex;
  final int selectedStageIndex;
  final _GalleryCharacter selected;
  final _GalleryStage selectedStage;
  final ValueChanged<int> onCharacterSelected;
  final ValueChanged<int> onStageSelected;

  @override
  State<_GalleryPlayerScaffold> createState() => _GalleryPlayerScaffoldState();
}

class _GalleryPlayerScaffoldState extends State<_GalleryPlayerScaffold> {
  bool _chromeVisible = true;

  void _toggleChrome() {
    final bool nextVisible = !_chromeVisible;
    setState(() {
      _chromeVisible = nextVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compactHeight = constraints.maxHeight < 560;
        final double sideInset = compactHeight ? 10 : 16;
        final double stripHeight = compactHeight ? 116 : 156;
        final double tileWidth = compactHeight ? 104 : 136;
        final double tileImageHeight = compactHeight ? 78 : 112;
        final double toggleWidth = compactHeight ? 44 : 52;

        return Stack(
          children: <Widget>[
            Positioned.fill(child: widget.player),
            Positioned(
              left: padding.left + sideInset,
              top: padding.top + sideInset,
              child: _PersistentOverlayVisibility(
                visible: _chromeVisible,
                child: _CharacterInfoPanel(
                  character: widget.selected,
                  stage: widget.selectedStage,
                  stageIndex: widget.selectedStageIndex,
                  onStageSelected: widget.onStageSelected,
                ),
              ),
            ),
            Positioned(
              left: padding.left + sideInset,
              right: padding.right + sideInset,
              bottom: padding.bottom + sideInset,
              height: stripHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _PersistentOverlayVisibility(
                      visible: _chromeVisible,
                      child: _CharacterStrip(
                        characters: widget.characters,
                        selectedIndex: widget.selectedCharacterIndex,
                        tileWidth: tileWidth,
                        tileImageHeight: tileImageHeight,
                        onSelected: widget.onCharacterSelected,
                      ),
                    ),
                  ),
                  SizedBox(width: compactHeight ? 8 : 10),
                  SizedBox(
                    width: toggleWidth,
                    child: _ChromeToggleButton(
                      visible: _chromeVisible,
                      onPressed: _toggleChrome,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersistentOverlayVisibility extends StatelessWidget {
  const _PersistentOverlayVisibility({
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

class _ChromeToggleButton extends StatelessWidget {
  const _ChromeToggleButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xD90B1018),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      child: Icon(
        visible
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: 30,
      ),
    );
  }
}

class _CharacterInfoPanel extends StatelessWidget {
  const _CharacterInfoPanel({
    required this.character,
    required this.stage,
    required this.stageIndex,
    required this.onStageSelected,
  });

  final _GalleryCharacter character;
  final _GalleryStage stage;
  final int stageIndex;
  final ValueChanged<int> onStageSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 310),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCC111823),
              border: Border.all(color: const Color(0x33FFFFFF)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    character.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${character.cardId}  ${stage.folder}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 15,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (character.stages.length > 1) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: List<Widget>.generate(character.stages.length, (
                int index,
              ) {
                return _StageButton(
                  label: '立绘${index + 1}',
                  selected: index == stageIndex,
                  onTap: () => onStageSelected(index),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageButton extends StatelessWidget {
  const _StageButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 106,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor:
              selected ? const Color(0xFFF5CB5C) : const Color(0xCC111823),
          foregroundColor: selected ? const Color(0xFF151515) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color:
                  selected ? const Color(0xFFFFE08B) : const Color(0x33FFFFFF),
            ),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _CharacterStrip extends StatelessWidget {
  const _CharacterStrip({
    required this.characters,
    required this.selectedIndex,
    required this.tileWidth,
    required this.tileImageHeight,
    required this.onSelected,
  });

  final List<_GalleryCharacter> characters;
  final int selectedIndex;
  final double tileWidth;
  final double tileImageHeight;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD90B1018),
        border: Border.all(color: const Color(0x33FFFFFF)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: characters.length,
        separatorBuilder: (BuildContext context, int index) {
          return const SizedBox(width: 10);
        },
        itemBuilder: (BuildContext context, int index) {
          final _GalleryCharacter character = characters[index];
          return _CharacterTile(
            character: character,
            selected: index == selectedIndex,
            width: tileWidth,
            imageHeight: tileImageHeight,
            onTap: () => onSelected(index),
          );
        },
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.selected,
    required this.width,
    required this.imageHeight,
    required this.onTap,
  });

  final _GalleryCharacter character;
  final bool selected;
  final double width;
  final double imageHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC101823),
            border: Border.all(
              color:
                  selected ? const Color(0xFFFFD75E) : const Color(0x33FFFFFF),
              width: selected ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: imageHeight,
                    width: width,
                    child:
                        character.portraitAssetPath == null
                            ? _TileFallback(text: character.cardId.toString())
                            : Image.asset(
                              character.portraitAssetPath!,
                              fit: BoxFit.contain,
                              alignment: Alignment.topCenter,
                              errorBuilder: (
                                BuildContext context,
                                Object error,
                                StackTrace? stackTrace,
                              ) {
                                return _TileFallback(
                                  text: character.cardId.toString(),
                                );
                              },
                            ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    color: const Color(0xB30B1018),
                    child: Text(
                      character.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
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
  const _TileFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF17212E),
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF080B12),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class _GalleryCharacter {
  const _GalleryCharacter({
    required this.cardId,
    required this.name,
    required this.nameCn,
    required this.portraitPath,
    required this.stages,
  });

  factory _GalleryCharacter.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawStages =
        json['stages'] as List<dynamic>? ?? <dynamic>[];
    return _GalleryCharacter(
      cardId: _asInt(json['cardId']),
      name: json['name']?.toString() ?? '',
      nameCn: json['nameCn']?.toString(),
      portraitPath: json['portraitPath']?.toString(),
      stages: rawStages
          .whereType<Map<String, dynamic>>()
          .map(_GalleryStage.fromJson)
          .toList(growable: false),
    );
  }

  final int cardId;
  final String name;
  final String? nameCn;
  final String? portraitPath;
  final List<_GalleryStage> stages;

  String get displayName => nameCn == null || nameCn!.isEmpty ? name : nameCn!;

  String? get portraitAssetPath => _assetPathFromManifestPath(portraitPath);
}

class _GalleryStage {
  const _GalleryStage({
    required this.folder,
    required this.stageName,
    required this.stageKey,
  });

  factory _GalleryStage.fromJson(Map<String, dynamic> json) {
    return _GalleryStage(
      folder: json['folder']?.toString() ?? '',
      stageName: json['stageName']?.toString() ?? '',
      stageKey: json['stageKey']?.toString() ?? '',
    );
  }

  final String folder;
  final String stageName;
  final String stageKey;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _assetPathFromManifestPath(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  final String normalized = path.startsWith('/') ? path.substring(1) : path;
  return 'assets/gallery_player/$normalized';
}

class EdenGalleryPlayerView extends StatefulWidget {
  const EdenGalleryPlayerView({
    super.key,
    this.options = const EdenGalleryPlayerOptions(),
    this.onEvent,
    this.backgroundColor = const Color(0xFF080B12),
    this.showLoadingOverlay = true,
  });

  final EdenGalleryPlayerOptions options;
  final ValueChanged<EdenGalleryPlayerEvent>? onEvent;
  final Color backgroundColor;
  final bool showLoadingOverlay;

  @override
  State<EdenGalleryPlayerView> createState() => EdenGalleryPlayerViewState();
}

class EdenGalleryPlayerViewState extends State<EdenGalleryPlayerView> {
  static const String _assetRoot = 'assets/gallery_player';
  static const String _embedAsset =
      '$_assetRoot/gallery-assets/spine_player/embed.html';
  static const String _embedPath = '/gallery-assets/spine_player/embed.html';

  late final WebViewController _controller;
  HttpServer? _assetServer;
  Uri? _serverRoot;
  EdenGalleryPlayerOptions? _pendingOptions;
  bool _apiReady = false;
  bool _isLoading = true;
  String? _error;
  EdenGalleryPlayerEvent? _lastEvent;

  EdenGalleryPlayerEvent? get lastEvent => _lastEvent;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _loadEmbed();
  }

  @override
  void didUpdateWidget(covariant EdenGalleryPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.signature != widget.options.signature) {
      load(widget.options);
    }
  }

  Future<void> load(EdenGalleryPlayerOptions options) async {
    if (!_apiReady) {
      _pendingOptions = options;
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      await _controller.runJavaScript(
        'window.EdenGalleryPlayer.load(${jsonEncode(options.toJson())});',
      );
    } catch (error, stackTrace) {
      debugPrint('[EdenGalleryPlayer][load-js-error] $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '执行播放器脚本失败：$error';
      });
    }
  }

  WebViewController _createController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor)
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint(
          '[EdenGalleryPlayer][console][${message.level.name}] '
          '${message.message}',
        );
      })
      ..addJavaScriptChannel(
        'EdenGalleryPlayerChannel',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            debugPrint('[EdenGalleryPlayer][page-finished]');
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            final String detail = _formatResourceError(error);
            debugPrint('[EdenGalleryPlayer][resource-error] $detail');
            if (!mounted) {
              return;
            }
            setState(() {
              _isLoading = false;
              _error = detail;
            });
          },
        ),
      );
  }

  Future<void> _loadEmbed() async {
    try {
      await _ensureAssetServer();
      final Uri uri = _embedUriFor(widget.options);
      debugPrint('[EdenGalleryPlayer][embed] $uri');
      await _controller.loadRequest(uri);
    } catch (error, stackTrace) {
      debugPrint('[EdenGalleryPlayer][embed-load-error] $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '加载播放器入口失败：$_embedAsset\n$error';
      });
    }
  }

  Future<void> _ensureAssetServer() async {
    if (_serverRoot != null) {
      return;
    }

    await rootBundle.loadString(_embedAsset);
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _assetServer = server;
    _serverRoot = Uri.parse('http://localhost:${server.port}');
    server.listen(_handleAssetRequest);
  }

  Uri _embedUriFor(EdenGalleryPlayerOptions options) {
    return _serverRoot!.replace(
      path: _embedPath,
      queryParameters: <String, String>{'config': jsonEncode(options.toJson())},
    );
  }

  Future<void> _handleAssetRequest(HttpRequest request) async {
    final HttpResponse response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    final String decodedPath = Uri.decodeComponent(
      request.uri.path.isEmpty || request.uri.path == '/'
          ? _embedPath
          : request.uri.path,
    );
    if (decodedPath.contains('..') || decodedPath.contains(r'\')) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }

    final String assetPath = '$_assetRoot$decodedPath';
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = _contentTypeFor(assetPath);
      response.contentLength = bytes.length;
      if (request.method != 'HEAD') {
        response.add(bytes);
      }
    } catch (error) {
      debugPrint('[EdenGalleryPlayer][asset-404] $assetPath $error');
      response.statusCode = HttpStatus.notFound;
      response.headers.contentType = ContentType.text;
      response.write('Not found: $assetPath');
    } finally {
      await response.close();
    }
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    debugPrint('[EdenGalleryPlayer][bridge] ${message.message}');
    final EdenGalleryPlayerEvent event = EdenGalleryPlayerEvent.fromMessage(
      message.message,
    );
    widget.onEvent?.call(event);

    if (!mounted) {
      return;
    }

    setState(() {
      _lastEvent = event;
      if (event.type == 'api-ready') {
        _apiReady = true;
      } else if (event.type == 'error') {
        _isLoading = false;
        _error = event.message ?? '立绘加载失败';
      } else if (event.type == 'ready') {
        _isLoading = false;
        _error = null;
      }
    });

    if (event.type == 'api-ready') {
      _flushPendingLoad();
    }
  }

  void _flushPendingLoad() {
    final EdenGalleryPlayerOptions? options = _pendingOptions;
    if (options == null) {
      return;
    }
    _pendingOptions = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      load(options);
    });
  }

  String _formatResourceError(WebResourceError error) {
    final List<String> lines = <String>[
      error.description,
      'code: ${error.errorCode}',
    ];
    if (error.errorType != null) {
      lines.add('type: ${error.errorType!.name}');
    }
    if (error.isForMainFrame != null) {
      lines.add('mainFrame: ${error.isForMainFrame}');
    }
    if (error.url != null && error.url!.isNotEmpty) {
      lines.add('url: ${error.url}');
    }
    return lines.join('\n');
  }

  ContentType _contentTypeFor(String assetPath) {
    final String path = assetPath.toLowerCase();
    if (path.endsWith('.html')) {
      return ContentType.html;
    }
    if (path.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (path.endsWith('.json')) {
      return ContentType.json;
    }
    if (path.endsWith('.png')) {
      return ContentType('image', 'png');
    }
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return ContentType('image', 'jpeg');
    }
    if (path.endsWith('.webp')) {
      return ContentType('image', 'webp');
    }
    if (path.endsWith('.gif')) {
      return ContentType('image', 'gif');
    }
    if (path.endsWith('.wav')) {
      return ContentType('audio', 'wav');
    }
    if (path.endsWith('.mp3')) {
      return ContentType('audio', 'mpeg');
    }
    if (path.endsWith('.ogg')) {
      return ContentType('audio', 'ogg');
    }
    if (path.endsWith('.m4a') || path.endsWith('.aac')) {
      return ContentType('audio', 'aac');
    }
    if (path.endsWith('.ico')) {
      return ContentType('image', 'x-icon');
    }
    if (path.endsWith('.wasm')) {
      return ContentType('application', 'wasm');
    }
    if (path.endsWith('.atlas') ||
        path.endsWith('.prefab') ||
        path.endsWith('.txt')) {
      return ContentType.text;
    }
    return ContentType.binary;
  }

  @override
  void dispose() {
    _assetServer?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (widget.showLoadingOverlay && _isLoading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

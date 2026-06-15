import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../global/eden_gallery_favorites_store.dart';
import '../../global/eden_gallery_player_globals.dart';

typedef _JsonMap = Map<String, dynamic>;

class EdenRemotePlayerPage extends StatefulWidget {
  const EdenRemotePlayerPage({
    super.key,
    this.baseUrl,
    this.config = const <String, Object?>{
      'cardId': 11100001,
      'stageIndex': 0,
      'showStatus': true,
    },
  });

  /// Optional external debug server. When null, the page serves bundled
  /// gallery assets through an in-app localhost server.
  final String? baseUrl;
  final Map<String, Object?> config;

  @override
  State<EdenRemotePlayerPage> createState() => _EdenRemotePlayerPageState();
}

class _EdenRemotePlayerPageState extends State<EdenRemotePlayerPage> {
  static const Color _backgroundColor =
      EdenGalleryPlayerGlobals.pageBackgroundColor;
  static const String _assetRoot = 'assets/gallery_player';
  static const String _embedAsset =
      '$_assetRoot/gallery-assets/spine_player/embed.html';
  static const String _embedPath = '/gallery-assets/spine_player/embed.html';

  late final WebViewController _controller;
  late Future<List<_RemoteGalleryCharacter>> _charactersFuture;
  final Random _voiceRandom = Random();

  HttpServer? _assetServer;
  Uri? _serverRoot;
  List<_RemoteGalleryCharacter> _loadedCharacters =
      const <_RemoteGalleryCharacter>[];
  Set<int> _favoriteCharacterIds = <int>{};
  Map<int, int> _characterOrderByCardId = const <int, int>{};
  Map<String, Object?> _currentConfig = const <String, Object?>{};
  Map<String, Object?>? _pendingConfig;
  Uri? _playerUri;
  bool _apiReady = false;
  bool _isLoading = true;
  bool _voicePlaying = false;
  bool _chromeVisible = true;
  String? _error;
  _RemoteVoiceLine? _subtitleVoiceLine;
  int _selectedCharacterIndex = 0;
  int _selectedStageIndex = 0;
  bool _selectionResolved = false;
  int _voiceToken = 0;

  @override
  void initState() {
    super.initState();
    _currentConfig = _copyConfig(widget.config);
    _controller = _createController();
    _charactersFuture = _bootstrapPlayer();
  }

  @override
  void didUpdateWidget(covariant EdenRemotePlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool baseChanged = oldWidget.baseUrl != widget.baseUrl;
    final bool configChanged =
        _configSignature(oldWidget.config) != _configSignature(widget.config);
    if (!baseChanged && !configChanged) {
      return;
    }

    _currentConfig = _copyConfig(widget.config);
    _selectionResolved = false;
    if (baseChanged) {
      _stopVoicePlayback();
      setState(() {
        _apiReady = false;
        _pendingConfig = null;
        _isLoading = true;
        _error = null;
        _charactersFuture = _restartPlayerService();
      });
      return;
    }

    _charactersFuture.then((List<_RemoteGalleryCharacter> characters) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resolveInitialSelection(characters);
      });
    });
    _loadConfig(_currentConfig);
  }

  Future<List<_RemoteGalleryCharacter>> _bootstrapPlayer() async {
    _favoriteCharacterIds =
        await EdenGalleryFavoritesStore.loadFavoriteCardIds();
    await _ensureServerRoot();
    await _loadInitialPlayer();
    return _loadCharacters();
  }

  Future<List<_RemoteGalleryCharacter>> _restartPlayerService() async {
    final HttpServer? server = _assetServer;
    _assetServer = null;
    _serverRoot = null;
    await server?.close(force: true);
    return _bootstrapPlayer();
  }

  Future<void> _loadInitialPlayer() async {
    await _ensureServerRoot();
    _apiReady = false;
    _pendingConfig = null;
    _playerUri = _buildPlayerUri(_currentConfig);
    debugPrint('[EdenRemotePlayer][url] $_playerUri');
    await _controller.loadRequest(_playerUri!);
  }

  Future<List<_RemoteGalleryCharacter>> _loadCharacters() async {
    await _ensureServerRoot();
    final Uri manifestUri = _buildServiceUri('/gallery-assets/manifest.json');
    debugPrint('[EdenRemotePlayer][manifest] $manifestUri');
    final Map<String, dynamic> manifest = await _fetchJson(manifestUri);
    final Map<int, List<_RemoteVoiceLine>> voicesByCardId =
        await _loadVoicesByCardId();
    final List<dynamic> rawCharacters =
        manifest['characters'] as List<dynamic>? ?? <dynamic>[];
    final List<_RemoteGalleryCharacter> characters = rawCharacters
        .whereType<Map<String, dynamic>>()
        .map((_JsonMap json) {
          final int cardId = _asInt(json['cardId']);
          return _RemoteGalleryCharacter.fromJson(
            json,
            voiceLines: voicesByCardId[cardId] ?? const <_RemoteVoiceLine>[],
          );
        })
        .where((_RemoteGalleryCharacter character) {
          return character.stages.isNotEmpty;
        })
        .toList(growable: false);
    _characterOrderByCardId = <int, int>{
      for (int index = 0; index < characters.length; index += 1)
        characters[index].cardId: index,
    };
    _loadedCharacters = _sortCharacters(characters);
    return _loadedCharacters;
  }

  Future<Map<int, List<_RemoteVoiceLine>>> _loadVoicesByCardId() async {
    final Uri infoUri = _buildServiceUri(
      '/gallery-assets/file/character_info_manifest.json',
    );
    debugPrint('[EdenRemotePlayer][voice-manifest] $infoUri');
    final Map<String, dynamic> manifest = await _fetchJson(infoUri);
    final Object? rawCards = manifest['cards'];
    final Iterable<dynamic> cards =
        rawCards is Map ? rawCards.values : const <dynamic>[];
    final Map<int, List<_RemoteVoiceLine>> result =
        <int, List<_RemoteVoiceLine>>{};

    for (final dynamic rawCard in cards) {
      if (rawCard is! Map) {
        continue;
      }
      final int cardId = _asInt(rawCard['id']);
      if (cardId == 0) {
        continue;
      }
      final List<_RemoteVoiceLine> voiceLines =
          (rawCard['voiceLines'] as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(_RemoteVoiceLine.fromJson)
              .whereType<_RemoteVoiceLine>()
              .where((_RemoteVoiceLine voiceLine) => !voiceLine.excluded)
              .toList(growable: false);
      result[cardId] = voiceLines;
    }

    return result;
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response = await request.close();
      final String text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'JSON load failed: HTTP ${response.statusCode}\n$text',
        );
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Uri _buildPlayerUri(Map<String, Object?> config) {
    return _buildServiceUri(
      _embedPath,
    ).replace(queryParameters: <String, String>{'config': jsonEncode(config)});
  }

  Uri _buildServiceUri(String path) {
    final Uri? root = _serverRoot;
    if (root == null) {
      throw StateError('Eden gallery asset service is not ready.');
    }
    final String normalizedPath = path.startsWith('/') ? path : '/$path';
    return root.replace(path: normalizedPath);
  }

  Future<void> _ensureServerRoot() async {
    if (_serverRoot != null) {
      return;
    }

    final String? externalBaseUrl = widget.baseUrl;
    if (externalBaseUrl != null && externalBaseUrl.trim().isNotEmpty) {
      final String normalizedBase =
          externalBaseUrl.endsWith('/')
              ? externalBaseUrl.substring(0, externalBaseUrl.length - 1)
              : externalBaseUrl;
      _serverRoot = Uri.parse(normalizedBase);
      return;
    }

    await rootBundle.loadString(_embedAsset);
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _assetServer = server;
    _serverRoot = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen(_handleAssetRequest);
    debugPrint('[EdenRemotePlayer][asset-server] $_serverRoot');
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
      debugPrint('[EdenRemotePlayer][asset-404] $assetPath $error');
      response.statusCode = HttpStatus.notFound;
      response.headers.contentType = ContentType.text;
      response.write('Not found: $assetPath');
    } finally {
      await response.close();
    }
  }

  WebViewController _createController() {
    final WebViewController controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(_backgroundColor)
          ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
            debugPrint(
              '[EdenRemotePlayer][console][${message.level.name}] '
              '${message.message}',
            );
          })
          ..addJavaScriptChannel(
            'EdenGalleryPlayerChannel',
            onMessageReceived: _handleBridgeMessage,
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
              },
              onPageFinished: (_) {
                debugPrint('[EdenRemotePlayer][page-finished]');
              },
              onWebResourceError: (WebResourceError error) {
                final String detail =
                    'code=${error.errorCode}, type=${error.errorType}, '
                    'mainFrame=${error.isForMainFrame}, '
                    'description=${error.description}';
                debugPrint('[EdenRemotePlayer][resource-error] $detail');
                if (error.isForMainFrame == false || !mounted) {
                  return;
                }
                setState(() {
                  _isLoading = false;
                  _error = detail;
                });
              },
            ),
          );

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    return controller;
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    debugPrint('[EdenRemotePlayer][bridge] ${message.message}');
    final _RemotePlayerEvent event = _RemotePlayerEvent.fromMessage(
      message.message,
    );

    if (event.type == 'voice-ended' || event.type == 'voice-error') {
      if (event.type == 'voice-error') {
        debugPrint('[EdenRemotePlayer][voice-error] ${event.message ?? ''}');
      }
      _finishVoice(_intValue(event.payload['token']));
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
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
      _flushPendingConfig();
    }
  }

  Future<void> _handleWebViewTap() async {
    if (_voicePlaying || _error != null) {
      return;
    }

    final _RemoteGalleryCharacter? character = _selectedCharacterForVoice();
    if (character == null || character.voiceLines.isEmpty) {
      return;
    }

    final _RemoteVoiceLine voiceLine =
        character.voiceLines[_voiceRandom.nextInt(character.voiceLines.length)];
    await _playVoice(voiceLine);
  }

  _RemoteGalleryCharacter? _selectedCharacterForVoice() {
    if (_loadedCharacters.isEmpty) {
      return null;
    }
    final int safeIndex = _selectedCharacterIndex.clamp(
      0,
      _loadedCharacters.length - 1,
    );
    return _loadedCharacters[safeIndex];
  }

  Future<void> _playVoice(_RemoteVoiceLine voiceLine) async {
    final int token = _voiceToken + 1;
    _voiceToken = token;
    if (mounted) {
      setState(() {
        _voicePlaying = true;
        _subtitleVoiceLine = voiceLine;
      });
    }

    final String audioUrl = _buildServiceUri(voiceLine.audioPath).toString();
    final String script = '''
(function () {
  var token = $token;
  var url = ${jsonEncode(audioUrl)};
  function post(type, payload) {
    if (
      window.EdenGalleryPlayerChannel &&
      typeof window.EdenGalleryPlayerChannel.postMessage === 'function'
    ) {
      window.EdenGalleryPlayerChannel.postMessage(JSON.stringify({
        source: 'eden-flutter-voice',
        type: type,
        payload: payload || {},
        requestId: ''
      }));
    }
  }
  try {
    if (window.__edenFlutterVoiceAudio) {
      window.__edenFlutterVoiceAudio.onended = null;
      window.__edenFlutterVoiceAudio.onerror = null;
      window.__edenFlutterVoiceAudio.pause();
    }
    var audio = new Audio(url);
    window.__edenFlutterVoiceAudio = audio;
    window.__edenFlutterVoiceToken = token;
    audio.preload = 'auto';
    audio.onended = function () {
      post('voice-ended', {token: token});
    };
    audio.onerror = function () {
      post('voice-error', {
        token: token,
        message: 'audio load failed: ' + url
      });
    };
    var promise = audio.play();
    if (promise && typeof promise.catch === 'function') {
      promise.catch(function (error) {
        post('voice-error', {
          token: token,
          message: String(error && (error.message || error) || 'play failed')
        });
      });
    }
  } catch (error) {
    post('voice-error', {
      token: token,
      message: String(error && (error.message || error) || error)
    });
  }
})();
''';

    try {
      await _controller.runJavaScript(script);
    } catch (error, stackTrace) {
      debugPrint('[EdenRemotePlayer][voice-js-error] $error');
      debugPrint('$stackTrace');
      _finishVoice(token);
    }
  }

  Future<void> _stopVoicePlayback({bool clearSubtitle = true}) async {
    _voiceToken += 1;
    if (mounted) {
      setState(() {
        _voicePlaying = false;
        if (clearSubtitle) {
          _subtitleVoiceLine = null;
        }
      });
    } else {
      _voicePlaying = false;
      if (clearSubtitle) {
        _subtitleVoiceLine = null;
      }
    }

    const String script = '''
(function () {
  if (window.__edenFlutterVoiceAudio) {
    window.__edenFlutterVoiceAudio.onended = null;
    window.__edenFlutterVoiceAudio.onerror = null;
    window.__edenFlutterVoiceAudio.pause();
    try {
      window.__edenFlutterVoiceAudio.currentTime = 0;
    } catch (error) {}
  }
  window.__edenFlutterVoiceAudio = null;
  window.__edenFlutterVoiceToken = null;
})();
''';

    try {
      await _controller.runJavaScript(script);
    } catch (error) {
      debugPrint('[EdenRemotePlayer][voice-stop-js-error] $error');
    }
  }

  void _finishVoice(int? token) {
    if (token != _voiceToken) {
      return;
    }
    if (!mounted) {
      _voicePlaying = false;
      _subtitleVoiceLine = null;
      return;
    }
    setState(() {
      _voicePlaying = false;
      _subtitleVoiceLine = null;
    });
  }

  Future<void> _loadConfig(Map<String, Object?> config) async {
    _currentConfig = _copyConfig(config);
    if (!_apiReady) {
      _pendingConfig = _copyConfig(config);
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
        'window.EdenGalleryPlayer.load(${jsonEncode(config)});',
      );
    } catch (error, stackTrace) {
      debugPrint('[EdenRemotePlayer][load-js-error] $error');
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

  void _flushPendingConfig() {
    final Map<String, Object?>? config = _pendingConfig;
    if (config == null) {
      return;
    }
    _pendingConfig = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadConfig(config);
      }
    });
  }

  void _resolveInitialSelection(List<_RemoteGalleryCharacter> characters) {
    if (_selectionResolved || characters.isEmpty) {
      return;
    }

    int characterIndex = _intValue(_currentConfig['characterIndex']) ?? 0;
    int stageIndex =
        _intValue(_currentConfig['stageIndex']) ??
        ((_intValue(_currentConfig['stageNo']) ?? 1) - 1);

    final String? requestedCardId = _stringValue(_currentConfig['cardId']);
    final String? requestedFolder = _stringValue(_currentConfig['folder']);
    final String? requestedStageFolder = _stringValue(
      _currentConfig['stageFolder'],
    );
    final String? requestedStageKey = _stringValue(_currentConfig['stageKey']);
    final String? requestedStageName = _stringValue(
      _currentConfig['stageName'],
    );

    for (int index = 0; index < characters.length; index += 1) {
      final _RemoteGalleryCharacter character = characters[index];
      final bool cardMatched =
          requestedCardId != null &&
          character.cardId.toString() == requestedCardId;
      final int matchedStageIndex = character.stages.indexWhere(
        (_RemoteGalleryStage stage) =>
            (requestedFolder != null && stage.folder == requestedFolder) ||
            (requestedStageFolder != null &&
                stage.folder == requestedStageFolder) ||
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

  List<_RemoteGalleryCharacter> _sortCharacters(
    List<_RemoteGalleryCharacter> characters, {
    Set<int>? favoriteCharacterIds,
  }) {
    final Set<int> favoriteIds = favoriteCharacterIds ?? _favoriteCharacterIds;
    final List<_RemoteGalleryCharacter> sorted =
        List<_RemoteGalleryCharacter>.of(characters);
    sorted.sort((_RemoteGalleryCharacter a, _RemoteGalleryCharacter b) {
      final bool aFavorite = favoriteIds.contains(a.cardId);
      final bool bFavorite = favoriteIds.contains(b.cardId);
      if (aFavorite != bFavorite) {
        return aFavorite ? -1 : 1;
      }
      final int aOrder = _characterOrderByCardId[a.cardId] ?? a.cardId;
      final int bOrder = _characterOrderByCardId[b.cardId] ?? b.cardId;
      return aOrder.compareTo(bOrder);
    });
    return sorted;
  }

  int _indexForCardId(List<_RemoteGalleryCharacter> characters, int cardId) {
    final int index = characters.indexWhere(
      (_RemoteGalleryCharacter character) => character.cardId == cardId,
    );
    return index < 0 ? 0 : index;
  }

  Future<void> _toggleFavoriteCharacter(
    _RemoteGalleryCharacter character,
  ) async {
    final int? selectedCardId = _selectedCharacterForVoice()?.cardId;
    final Set<int> nextFavorites = Set<int>.of(_favoriteCharacterIds);
    if (!nextFavorites.add(character.cardId)) {
      nextFavorites.remove(character.cardId);
    }
    final List<_RemoteGalleryCharacter> sortedCharacters = _sortCharacters(
      _loadedCharacters,
      favoriteCharacterIds: nextFavorites,
    );

    setState(() {
      _favoriteCharacterIds = nextFavorites;
      _loadedCharacters = sortedCharacters;
      _selectedCharacterIndex =
          selectedCardId == null
              ? _selectedCharacterIndex.clamp(0, _loadedCharacters.length - 1)
              : _indexForCardId(_loadedCharacters, selectedCardId);
      _charactersFuture = Future<List<_RemoteGalleryCharacter>>.value(
        _loadedCharacters,
      );
    });

    try {
      await EdenGalleryFavoritesStore.saveFavoriteCardIds(
        _favoriteCharacterIds,
      );
    } catch (error, stackTrace) {
      debugPrint('[EdenRemotePlayer][favorite-save-error] $error');
      debugPrint('$stackTrace');
    }
  }

  void _selectCharacter(List<_RemoteGalleryCharacter> characters, int index) {
    final int safeIndex = index.clamp(0, characters.length - 1);
    final _RemoteGalleryCharacter character = characters[safeIndex];
    final _RemoteGalleryCharacter? previous = _selectedCharacterForVoice();
    if (previous != null && previous.cardId != character.cardId) {
      _stopVoicePlayback();
    }
    setState(() {
      _selectedCharacterIndex = safeIndex;
      _selectedStageIndex = 0;
    });
    _loadConfig(_configFor(character, 0));
  }

  void _selectStage(_RemoteGalleryCharacter character, int index) {
    final int safeIndex = index.clamp(0, character.stages.length - 1);
    setState(() {
      _selectedStageIndex = safeIndex;
    });
    _loadConfig(_configFor(character, safeIndex));
  }

  Map<String, Object?> _configFor(
    _RemoteGalleryCharacter character,
    int stageIndex,
  ) {
    final Map<String, Object?> result = _copyConfig(widget.config);
    const List<String> selectorKeys = <String>[
      'cardId',
      'characterId',
      'id',
      'characterIndex',
      'folder',
      'stageFolder',
      'stageName',
      'stageKey',
      'stageIndex',
      'stageNumber',
      'stageNo',
      'variant',
      'variantIndex',
      'portrait',
      'portraitIndex',
      'skinIndex',
    ];
    for (final String key in selectorKeys) {
      result.remove(key);
    }
    result['cardId'] = character.cardId;
    result['stageIndex'] = stageIndex;
    if (!result.containsKey('showStatus')) {
      result['showStatus'] = widget.config['showStatus'] ?? true;
    }
    return result;
  }

  String? _remoteAssetUrl(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _buildServiceUri(path).toString();
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible == visible) {
      return;
    }
    setState(() {
      _chromeVisible = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? subtitleText = _subtitleVoiceLine?.subtitleFor(
      EdenGalleryPlayerGlobals.subtitleLanguage,
    );
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleWebViewTap,
            ),
          ),
          FutureBuilder<List<_RemoteGalleryCharacter>>(
            future: _charactersFuture,
            initialData: _loadedCharacters.isEmpty ? null : _loadedCharacters,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<_RemoteGalleryCharacter>> snapshot,
            ) {
              if (snapshot.hasError) {
                return _RemoteControlsError(
                  message: '角色列表加载失败\n${snapshot.error}',
                );
              }

              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              final List<_RemoteGalleryCharacter> characters = snapshot.data!;
              if (characters.isEmpty) {
                return const _RemoteControlsError(message: '没有找到可展示的角色资源');
              }

              _resolveInitialSelection(characters);
              final int safeCharacterIndex = _selectedCharacterIndex.clamp(
                0,
                characters.length - 1,
              );
              final _RemoteGalleryCharacter selected =
                  characters[safeCharacterIndex];
              final int safeStageIndex = _selectedStageIndex.clamp(
                0,
                selected.stages.length - 1,
              );
              final _RemoteGalleryStage selectedStage =
                  selected.stages[safeStageIndex];

              return _RemotePlayerScaffold(
                characters: characters,
                selectedCharacterIndex: safeCharacterIndex,
                selectedStageIndex: safeStageIndex,
                selected: selected,
                selectedStage: selectedStage,
                chromeVisible: _chromeVisible,
                subtitleText: subtitleText,
                favoriteCharacterIds: _favoriteCharacterIds,
                assetUrlBuilder: _remoteAssetUrl,
                onCharacterSelected: (int index) {
                  _selectCharacter(characters, index);
                },
                onStageSelected: (int index) {
                  _selectStage(selected, index);
                },
                onFavoriteToggled: _toggleFavoriteCharacter,
                onChromeVisibilityChanged: _setChromeVisible,
              );
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
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
                    '立绘页面加载失败\n$_error\n$_playerUri',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Map<String, Object?> _copyConfig(Map<String, Object?> config) {
    return <String, Object?>{...config};
  }

  static String _configSignature(Map<String, Object?> config) {
    return jsonEncode(config);
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
}

class _RemotePlayerEvent {
  const _RemotePlayerEvent({required this.type, required this.payload});

  final String type;
  final Map<String, Object?> payload;

  String? get message {
    final Object? value = payload['message'];
    return value?.toString();
  }

  factory _RemotePlayerEvent.fromMessage(String message) {
    try {
      final Object? decoded = jsonDecode(message);
      if (decoded is Map) {
        return _RemotePlayerEvent(
          type: (decoded['type'] ?? '').toString(),
          payload: _asMap(decoded['payload']),
        );
      }
    } catch (_) {
      // Keep raw messages visible in the console through the caller's log.
    }

    return _RemotePlayerEvent(
      type: 'message',
      payload: <String, Object?>{'message': message},
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

class _RemotePlayerScaffold extends StatelessWidget {
  const _RemotePlayerScaffold({
    required this.characters,
    required this.selectedCharacterIndex,
    required this.selectedStageIndex,
    required this.selected,
    required this.selectedStage,
    required this.chromeVisible,
    required this.subtitleText,
    required this.favoriteCharacterIds,
    required this.assetUrlBuilder,
    required this.onCharacterSelected,
    required this.onStageSelected,
    required this.onFavoriteToggled,
    required this.onChromeVisibilityChanged,
  });

  final List<_RemoteGalleryCharacter> characters;
  final int selectedCharacterIndex;
  final int selectedStageIndex;
  final _RemoteGalleryCharacter selected;
  final _RemoteGalleryStage selectedStage;
  final bool chromeVisible;
  final String? subtitleText;
  final Set<int> favoriteCharacterIds;
  final String? Function(String? path) assetUrlBuilder;
  final ValueChanged<int> onCharacterSelected;
  final ValueChanged<int> onStageSelected;
  final ValueChanged<_RemoteGalleryCharacter> onFavoriteToggled;
  final ValueChanged<bool> onChromeVisibilityChanged;

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
            Positioned(
              left: padding.left + sideInset,
              top: padding.top + sideInset,
              child: _PersistentOverlayVisibility(
                visible: chromeVisible,
                child: _CharacterInfoPanel(
                  character: selected,
                  stage: selectedStage,
                  stageIndex: selectedStageIndex,
                  onStageSelected: onStageSelected,
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
                      visible: chromeVisible,
                      child: _CharacterStrip(
                        characters: characters,
                        selectedIndex: selectedCharacterIndex,
                        favoriteCharacterIds: favoriteCharacterIds,
                        tileWidth: tileWidth,
                        tileImageHeight: tileImageHeight,
                        assetUrlBuilder: assetUrlBuilder,
                        onSelected: onCharacterSelected,
                        onFavoriteToggled: onFavoriteToggled,
                      ),
                    ),
                  ),
                  SizedBox(width: compactHeight ? 8 : 10),
                  SizedBox(
                    width: toggleWidth,
                    child: _ChromeToggleButton(
                      visible: chromeVisible,
                      onPressed:
                          () => onChromeVisibilityChanged(!chromeVisible),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitleText != null)
              _VoiceSubtitle(
                text: subtitleText!,
                chromeVisible: chromeVisible,
                sideInset: sideInset,
                stripHeight: stripHeight,
                toggleWidth: toggleWidth,
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
        backgroundColor: EdenGalleryPlayerGlobals.panelBackgroundColor,
        foregroundColor: EdenGalleryPlayerGlobals.themeColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(
            color: EdenGalleryPlayerGlobals.panelBorderColor,
          ),
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

  final _RemoteGalleryCharacter character;
  final _RemoteGalleryStage stage;
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
                  label: '${index + 1}',
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
      width: 40,
      height: 40,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor:
              selected
                  ? EdenGalleryPlayerGlobals.themeColor
                  : const Color(0xCC111823),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color:
                  selected
                      ? EdenGalleryPlayerGlobals.themeColor
                      : const Color(0x33FFFFFF),
            ),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _CharacterStrip extends StatelessWidget {
  const _CharacterStrip({
    required this.characters,
    required this.selectedIndex,
    required this.favoriteCharacterIds,
    required this.tileWidth,
    required this.tileImageHeight,
    required this.assetUrlBuilder,
    required this.onSelected,
    required this.onFavoriteToggled,
  });

  final List<_RemoteGalleryCharacter> characters;
  final int selectedIndex;
  final Set<int> favoriteCharacterIds;
  final double tileWidth;
  final double tileImageHeight;
  final String? Function(String? path) assetUrlBuilder;
  final ValueChanged<int> onSelected;
  final ValueChanged<_RemoteGalleryCharacter> onFavoriteToggled;

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
          final _RemoteGalleryCharacter character = characters[index];
          return _CharacterTile(
            character: character,
            selected: index == selectedIndex,
            favorite: favoriteCharacterIds.contains(character.cardId),
            width: tileWidth,
            imageHeight: tileImageHeight,
            imageUrl: assetUrlBuilder(character.portraitPath),
            onTap: () => onSelected(index),
            onFavoriteToggled: () => onFavoriteToggled(character),
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
    required this.favorite,
    required this.width,
    required this.imageHeight,
    required this.imageUrl,
    required this.onTap,
    required this.onFavoriteToggled,
  });

  final _RemoteGalleryCharacter character;
  final bool selected;
  final bool favorite;
  final double width;
  final double imageHeight;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggled;

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
                  selected
                      ? EdenGalleryPlayerGlobals.themeColor
                      : const Color(0x33FFFFFF),
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
                        imageUrl == null
                            ? _TileFallback(text: character.cardId.toString())
                            : Image.network(
                              imageUrl!,
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
                Positioned(
                  right: 6,
                  bottom: 28,
                  child: _FavoriteButton(
                    favorite: favorite,
                    onTap: onFavoriteToggled,
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

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.favorite, required this.onTap});

  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        favorite
            ? EdenGalleryPlayerGlobals.themeColor
            : const Color(0xFF9AA3AF);
    return SizedBox(
      width: 32,
      height: 32,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            border: Border.all(color: const Color(0x40FFFFFF)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.favorite_rounded, color: color, size: 20),
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

class _VoiceSubtitle extends StatelessWidget {
  const _VoiceSubtitle({
    required this.text,
    required this.chromeVisible,
    required this.sideInset,
    required this.stripHeight,
    required this.toggleWidth,
  });

  final String text;
  final bool chromeVisible;
  final double sideInset;
  final double stripHeight;
  final double toggleWidth;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    final double bottom =
        padding.bottom + sideInset + (chromeVisible ? stripHeight + 10 : 0);
    final double rightInset =
        padding.right + sideInset + (chromeVisible ? 0 : toggleWidth + 12);
    return Positioned(
      left: padding.left + sideInset,
      right: rightInset,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: Center(
            key: ValueKey<String>(text),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteControlsError extends StatelessWidget {
  const _RemoteControlsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    return Positioned(
      left: padding.left + 16,
      top: padding.top + 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC111823),
            border: Border.all(color: const Color(0x33FFFFFF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteGalleryCharacter {
  const _RemoteGalleryCharacter({
    required this.cardId,
    required this.name,
    required this.nameCn,
    required this.portraitPath,
    required this.stages,
    required this.voiceLines,
  });

  factory _RemoteGalleryCharacter.fromJson(
    Map<String, dynamic> json, {
    List<_RemoteVoiceLine> voiceLines = const <_RemoteVoiceLine>[],
  }) {
    final List<dynamic> rawStages =
        json['stages'] as List<dynamic>? ?? <dynamic>[];
    return _RemoteGalleryCharacter(
      cardId: _asInt(json['cardId']),
      name: json['name']?.toString() ?? '',
      nameCn: json['nameCn']?.toString(),
      portraitPath: json['portraitPath']?.toString(),
      stages: rawStages
          .whereType<Map<String, dynamic>>()
          .map(_RemoteGalleryStage.fromJson)
          .toList(growable: false),
      voiceLines: voiceLines,
    );
  }

  final int cardId;
  final String name;
  final String? nameCn;
  final String? portraitPath;
  final List<_RemoteGalleryStage> stages;
  final List<_RemoteVoiceLine> voiceLines;

  String get displayName => nameCn == null || nameCn!.isEmpty ? name : nameCn!;
}

class _RemoteVoiceLine {
  const _RemoteVoiceLine({
    required this.voicePath,
    required this.text,
    required this.textCn,
    required this.sort,
    required this.name,
    required this.nameCn,
    required this.excluded,
  });

  factory _RemoteVoiceLine.fromJson(Map<String, dynamic> json) {
    final Object? rawDetail = json['detail'];
    final Map<String, dynamic> detail =
        rawDetail is Map<String, dynamic> ? rawDetail : json;
    final String voicePath = detail['voicePath']?.toString() ?? '';
    final String text = detail['text']?.toString().trim() ?? '';
    final String textCn = detail['textCn']?.toString().trim() ?? '';
    final int sort = _asInt(detail['sort']);
    final String name = detail['name']?.toString() ?? '';
    final String nameCn = detail['nameCn']?.toString() ?? '';
    return _RemoteVoiceLine(
      voicePath: voicePath,
      text: text,
      textCn: textCn,
      sort: sort,
      name: name,
      nameCn: nameCn,
      excluded: _isExcludedVoiceLine(
        voicePath: voicePath,
        sort: sort,
        name: name,
        nameCn: nameCn,
      ),
    );
  }

  final String voicePath;
  final String text;
  final String textCn;
  final int sort;
  final String name;
  final String nameCn;
  final bool excluded;

  String get audioPath => '/gallery-assets/voice/$voicePath.wav';

  String subtitleFor(EdenGallerySubtitleLanguage language) {
    switch (language) {
      case EdenGallerySubtitleLanguage.chinese:
        return _firstNonEmptyString(<Object?>[textCn, text, nameCn, name]) ??
            voicePath;
      case EdenGallerySubtitleLanguage.japanese:
        return _firstNonEmptyString(<Object?>[text, textCn, name, nameCn]) ??
            voicePath;
    }
  }

  static bool _isExcludedVoiceLine({
    required String voicePath,
    required int sort,
    required String name,
    required String nameCn,
  }) {
    if (voicePath.isEmpty) {
      return true;
    }

    if (sort >= 70 && sort <= 130) {
      return true;
    }

    final String normalizedPath = voicePath.toLowerCase();
    if (normalizedPath.contains('battle_n') ||
        normalizedPath.contains('battle_hit') ||
        normalizedPath.contains('battle_h') ||
        normalizedPath.contains('battle_c') ||
        normalizedPath.contains('battle_die') ||
        normalizedPath.endsWith('_win_1') ||
        normalizedPath.contains('_win_') ||
        normalizedPath.endsWith('_fail_1') ||
        normalizedPath.contains('_fail_')) {
      return true;
    }

    final String label = '$name $nameCn';
    return label.contains('攻撃') ||
        label.contains('被ダメージ') ||
        label.contains('特技') ||
        label.contains('奥義') ||
        label.contains('戦闘勝利') ||
        label.contains('戦闘失敗') ||
        label.contains('普通攻击') ||
        label.contains('受击') ||
        label.contains('技能') ||
        label.contains('必杀') ||
        label.contains('胜利') ||
        label.contains('失败');
  }
}

class _RemoteGalleryStage {
  const _RemoteGalleryStage({
    required this.folder,
    required this.stageName,
    required this.stageKey,
  });

  factory _RemoteGalleryStage.fromJson(Map<String, dynamic> json) {
    return _RemoteGalleryStage(
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

String? _firstNonEmptyString(List<Object?> values) {
  for (final Object? value in values) {
    final String text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

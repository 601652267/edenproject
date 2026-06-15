import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SpineShowcasePage extends StatefulWidget {
  const SpineShowcasePage({super.key});

  @override
  State<SpineShowcasePage> createState() => _SpineShowcasePageState();
}

class _SpineShowcasePageState extends State<SpineShowcasePage> {
  static const String _assetBase = 'assets/file/CardShowSpine_11300018_3';
  static const String _assetName = 'CardShowSpine_11300018_3';
  static const String _spineRuntimeAsset = 'assets/spine_player/spine-ts.js';

  late final Future<WebViewController> _controllerFuture;
  bool _isPlaying = true;
  bool _isPlayerReady = false;
  String? _playerError;

  @override
  void initState() {
    super.initState();
    _controllerFuture = _createController();
  }

  Future<WebViewController> _createController() async {
    final String html = await _buildPlayerHtml();
    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF080B12))
      ..addJavaScriptChannel(
        'SpineBridge',
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) {
            return;
          }

          final String value = message.message;
          if (value == 'ready') {
            setState(() {
              _isPlayerReady = true;
              _playerError = null;
            });
          } else if (value.startsWith('error:')) {
            setState(() {
              _isPlayerReady = true;
              _playerError = value.substring('error:'.length);
            });
          }
        },
      );

    await controller.loadHtmlString(html);
    return controller;
  }

  Future<String> _buildPlayerHtml() async {
    final List<Object> loaded = await Future.wait<Object>(<Future<Object>>[
      rootBundle.loadString(_spineRuntimeAsset),
      rootBundle.loadString('$_assetBase/$_assetName.atlas'),
      rootBundle.load('$_assetBase/$_assetName.skel'),
      rootBundle.load('$_assetBase/$_assetName.png'),
    ]);

    final String spineRuntimeSource = _escapeScript(loaded[0] as String);
    final String atlasSource = loaded[1] as String;
    final Uint8List skelBytes = (loaded[2] as ByteData).buffer.asUint8List();
    final Uint8List textureBytes = (loaded[3] as ByteData).buffer.asUint8List();

    final String atlasJson = jsonEncode(atlasSource);
    final String skeletonJson = jsonEncode(base64Encode(skelBytes));
    final String textureJson = jsonEncode(base64Encode(textureBytes));

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body, #stage {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #080b12;
    }

    canvas {
      display: block;
      width: 100%;
      height: 100%;
      touch-action: none;
    }
  </style>
</head>
<body>
  <canvas id="stage"></canvas>
  <script>$spineRuntimeSource</script>
  <script>
    const spineAsset = {
      atlas: $atlasJson,
      skeleton: $skeletonJson,
      texture: $textureJson
    };

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

    function insetAtlasRegionUvs(atlas, image) {
      const textureWidth = Math.max(image.naturalWidth || image.width || 1, 1);
      const textureHeight = Math.max(image.naturalHeight || image.height || 1, 1);
      const halfTexelU = 0.5 / textureWidth;
      const halfTexelV = 0.5 / textureHeight;

      atlas.regions.forEach((region) => {
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

      const image = await loadImage(spineAsset.texture);
      const renderer = new spine.webgl.SceneRenderer(canvas, gl, true);
      const texture = new spine.webgl.GLTexture(gl, image, false);
      const atlas = new spine.TextureAtlas(spineAsset.atlas, () => texture);
      insetAtlasRegionUvs(atlas, image);
      const atlasLoader = new spine.AtlasAttachmentLoader(atlas);
      const binary = new spine.SkeletonBinary(atlasLoader);
      const skeletonData = binary.readSkeletonData(base64ToUint8Array(spineAsset.skeleton));
      const skeleton = new spine.Skeleton(skeletonData);
      const stateData = new spine.AnimationStateData(skeletonData);
      const state = new spine.AnimationState(stateData);
      const offset = new spine.Vector2();
      const size = new spine.Vector2();
      const boundsTemp = [];

      skeleton.setToSetupPose();
      skeleton.updateWorldTransform();

      const animationNames = skeletonData.animations.map((animation) => animation.name);
      const animation = animationNames.indexOf('idle') >= 0 ? 'idle' : animationNames[0];
      if (animation) {
        state.setAnimation(0, animation, true);
      }

      let playing = true;
      let lastFrameTime = performance.now() / 1000;
      let lastWidth = 0;
      let lastHeight = 0;

      function resize() {
        const ratio = Math.min(window.devicePixelRatio || 1, 2);
        const width = Math.max(Math.floor(canvas.clientWidth * ratio), 1);
        const height = Math.max(Math.floor(canvas.clientHeight * ratio), 1);
        if (canvas.width === width && canvas.height === height) {
          return false;
        }

        canvas.width = width;
        canvas.height = height;
        gl.viewport(0, 0, width, height);
        renderer.camera.setViewport(width, height);
        renderer.camera.update();
        lastWidth = width;
        lastHeight = height;
        return true;
      }

      function fitSkeleton() {
        skeleton.x = 0;
        skeleton.y = 0;
        skeleton.scaleX = 1;
        skeleton.scaleY = 1;
        skeleton.updateWorldTransform();
        skeleton.getBounds(offset, size, boundsTemp);

        const safeWidth = Math.max(size.x, 1);
        const safeHeight = Math.max(size.y, 1);
        const scale = Math.min(lastWidth / safeWidth, lastHeight / safeHeight) * 0.92;
        skeleton.scaleX = scale;
        skeleton.scaleY = scale;
        skeleton.x = -(offset.x + safeWidth * 0.5) * scale;
        skeleton.y = -(offset.y + safeHeight * 0.5) * scale;
        skeleton.updateWorldTransform();
      }

      function render(frameTimeMs) {
        if (resize()) {
          fitSkeleton();
        }

        const frameTime = frameTimeMs / 1000;
        const delta = Math.min(frameTime - lastFrameTime, 0.064);
        lastFrameTime = frameTime;

        if (playing) {
          state.update(delta);
          state.apply(skeleton);
          skeleton.updateWorldTransform();
        }

        gl.clearColor(0.031, 0.043, 0.071, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
        renderer.begin();
        renderer.drawSkeleton(skeleton, true);
        renderer.end();
        window.requestAnimationFrame(render);
      }

      window.currentSpine = skeleton;
      window.currentSpineState = state;
      window.currentAnimationName = animation || '';
      window.spineControls = {
        play() {
          playing = true;
          lastFrameTime = performance.now() / 1000;
        },
        pause() {
          playing = false;
        },
        restart() {
          if (animation) {
            state.setAnimation(0, animation, true);
            state.update(0);
            state.apply(skeleton);
            fitSkeleton();
          }
          playing = true;
          lastFrameTime = performance.now() / 1000;
        }
      };

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

  String _escapeScript(String source) {
    return source.replaceAll('</script>', '<\\/script>');
  }

  Future<void> _runPlayerCommand(String command) async {
    final WebViewController controller = await _controllerFuture;
    await controller.runJavaScript(
      'window.spineControls && window.spineControls.$command();',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: SafeArea(
        child: FutureBuilder<WebViewController>(
          future: _controllerFuture,
          builder: (
            BuildContext context,
            AsyncSnapshot<WebViewController> snapshot,
          ) {
            if (snapshot.hasError) {
              return _FailureView(message: snapshot.error.toString());
            }

            if (!snapshot.hasData) {
              return const Center(child: _LoadingIndicator());
            }

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: WebViewWidget(controller: snapshot.data!),
                ),
                if (!_isPlayerReady) const Center(child: _LoadingIndicator()),
                Positioned(
                  left: 16.w,
                  top: 12.h,
                  right: 16.w,
                  child: _PlayerToolbar(
                    isPlaying: _isPlaying,
                    onPlayPause: () {
                      final bool nextPlaying = !_isPlaying;
                      setState(() {
                        _isPlaying = nextPlaying;
                      });
                      _runPlayerCommand(nextPlaying ? 'play' : 'pause');
                    },
                    onRestart: () {
                      setState(() {
                        _isPlaying = true;
                      });
                      _runPlayerCommand('restart');
                    },
                  ),
                ),
                if (_playerError != null)
                  Positioned(
                    left: 16.w,
                    right: 16.w,
                    bottom: 16.h,
                    child: _ErrorBanner(message: _playerError!),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerToolbar extends StatelessWidget {
  const _PlayerToolbar({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onRestart,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC111827),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'CardShowSpine 11300018 3',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            IconButton(
              tooltip: isPlaying ? '暂停' : '播放',
              iconSize: 24.r,
              padding: EdgeInsets.all(8.r),
              constraints: BoxConstraints.tightFor(width: 44.w, height: 44.w),
              onPressed: onPlayPause,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            SizedBox(width: 4.w),
            IconButton(
              tooltip: '重播',
              iconSize: 24.r,
              padding: EdgeInsets.all(8.r),
              constraints: BoxConstraints.tightFor(width: 44.w, height: 44.w),
              onPressed: onRestart,
              icon: const Icon(Icons.replay),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6B42338),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.r),
        child: Text(
          message,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp, letterSpacing: 0),
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 40.r),
            SizedBox(height: 12.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, letterSpacing: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32.r,
      height: 32.r,
      child: CircularProgressIndicator(strokeWidth: 3.r),
    );
  }
}

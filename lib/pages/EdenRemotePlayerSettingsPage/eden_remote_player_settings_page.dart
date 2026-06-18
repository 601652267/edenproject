import 'package:flutter/material.dart';

import '../../global/eden_gallery_player_globals.dart';
import '../EdenDefaultBackgroundPage/eden_default_background_page.dart';

class EdenRemotePlayerSettingsPage extends StatefulWidget {
  const EdenRemotePlayerSettingsPage({
    super.key,
    required this.defaultBackgroundOptions,
    required this.selectedDefaultBackgroundPath,
  });

  final List<EdenDefaultBackgroundOption> defaultBackgroundOptions;
  final String? selectedDefaultBackgroundPath;

  @override
  State<EdenRemotePlayerSettingsPage> createState() =>
      _EdenRemotePlayerSettingsPageState();
}

class _EdenRemotePlayerSettingsPageState
    extends State<EdenRemotePlayerSettingsPage> {
  String? _defaultBackgroundPath;

  @override
  void initState() {
    super.initState();
    _defaultBackgroundPath = widget.selectedDefaultBackgroundPath;
  }

  void _commitAndPop() {
    Navigator.of(context).pop<String>(_defaultBackgroundPath ?? '');
  }

  Future<void> _openDefaultBackgroundPage() async {
    final String? result = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder:
            (BuildContext context) => EdenDefaultBackgroundPage(
              options: widget.defaultBackgroundOptions,
              selectedPath: _defaultBackgroundPath,
            ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _defaultBackgroundPath = result.isEmpty ? null : result;
    });
  }

  void _showVoiceImportPending() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('导入语音包功能稍后接入')));
  }

  String get _defaultBackgroundLabel {
    final String? path = _defaultBackgroundPath;
    if (path == null || path.isEmpty) {
      return '未选择';
    }
    for (final EdenDefaultBackgroundOption option
        in widget.defaultBackgroundOptions) {
      if (option.path == path) {
        return option.displayName;
      }
    }
    return '已选择';
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
        backgroundColor: EdenGalleryPlayerGlobals.defaultBgColor,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          scrolledUnderElevation: 0,
          title: const Text('设置', style: TextStyle(fontSize: 13),),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _commitAndPop,
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
            children: <Widget>[
              _SettingsTile(
                icon: Icons.image_rounded,
                title: '选择默认背景',
                trailingText: _defaultBackgroundLabel,
                onTap: _openDefaultBackgroundPage,
              ),
              const SizedBox(height: 10),
              _SettingsTile(
                icon: Icons.graphic_eq_rounded,
                title: '导入语音包',
                onTap: _showVoiceImportPending,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xA6080B12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x26FFFFFF)),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Icon(icon, color: EdenGalleryPlayerGlobals.themeColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailingText != null) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    trailingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

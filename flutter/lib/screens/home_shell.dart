import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/live_translate_service.dart';
import '../services/live_translate_settings.dart';
import 'conversation_screen.dart';
import 'language_setup_screen.dart';
import 'service_settings_dialog.dart';

enum _MicrophonePermission { prompt, granted, denied }

class HomeShell extends StatefulWidget {
  const HomeShell({
    this.translationClientFactory,
    this.audioPlayerFactory,
    this.settings,
    super.key,
  });

  final TranslationClientFactory? translationClientFactory;
  final TranslationAudioPlayerFactory? audioPlayerFactory;
  final LiveTranslateSettings? settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final LiveTranslateSettings _settings =
      widget.settings ?? LiveTranslateSettings.instance;
  LanguageOption _languageA = LanguageOption.chinese;
  LanguageOption _languageB = LanguageOption.english;
  _MicrophonePermission _permission = _MicrophonePermission.prompt;
  bool _showConversation = false;
  String? _entryError;
  List<TranscriptMessage> _messagesA = const [];
  List<TranscriptMessage> _messagesB = const [];

  Future<void> _requestStart() async {
    if (widget.translationClientFactory == null && !_settings.isConfigured) {
      setState(() => _entryError = '请先配置翻译服务');
      await _openSettings();
      return;
    }
    if (_permission != _MicrophonePermission.granted) {
      final allowed = await _showPermissionDialog();
      if (!mounted || allowed == null) return;
      if (!allowed) {
        setState(() {
          _permission = _MicrophonePermission.denied;
          _entryError = '需要允许麦克风权限才能开始对话';
        });
        _showToast('请允许麦克风权限后再开始对话');
        return;
      }
      _permission = _MicrophonePermission.granted;
    }

    setState(() {
      _entryError = null;
      _showConversation = true;
    });
  }

  Future<void> _openSettings() async {
    final saved = await showServiceSettingsDialog(
      context: context,
      settings: _settings,
    );
    if (!mounted || saved != true) return;
    setState(() => _entryError = null);
    _showToast('翻译服务配置已保存');
  }

  Future<bool?> _showPermissionDialog() {
    final denied = _permission == _MicrophonePermission.denied;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTone.primarySoft(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.mic_none_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              denied ? '需要麦克风权限' : '允许使用麦克风',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? '请在系统设置中允许麦克风访问，然后返回此处重试。'
                  : '同声需要麦克风来接收语音。录音会实时发送至阿里云百炼，用于语音识别、翻译和语音生成。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(context, false),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('暂不允许'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(denied ? '重新允许' : '允许'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.center)),
      );
  }

  void _setLanguages(LanguageOption languageA, LanguageOption languageB) {
    setState(() {
      _languageA = languageA;
      _languageB = languageB;
      _entryError = null;
    });
  }

  void _addMessage(PartySide target, TranscriptMessage message) {
    setState(() {
      if (target == PartySide.a) {
        _messagesA = [..._messagesA, message];
      } else {
        _messagesB = [..._messagesB, message];
      }
    });
  }

  void _clearMessages() {
    setState(() {
      _messagesA = const [];
      _messagesB = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          final enteringConversation =
              child.key == const ValueKey('conversation');
          final begin = Offset(enteringConversation ? 0.06 : -0.06, 0);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: begin,
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _showConversation
            ? ConversationScreen(
                key: const ValueKey('conversation'),
                languageA: _languageA,
                languageB: _languageB,
                messagesA: _messagesA,
                messagesB: _messagesB,
                onLanguagesChanged: _setLanguages,
                onEditLanguages: () =>
                    setState(() => _showConversation = false),
                onMessage: _addMessage,
                onClearMessages: _clearMessages,
                translationClientFactory: widget.translationClientFactory,
                audioPlayerFactory: widget.audioPlayerFactory,
              )
            : LanguageSetupScreen(
                key: const ValueKey('setup'),
                languageA: _languageA,
                languageB: _languageB,
                errorText: _entryError,
                onLanguagesChanged: _setLanguages,
                onStart: _requestStart,
                onOpenSettings: _openSettings,
              ),
      ),
    );
  }
}

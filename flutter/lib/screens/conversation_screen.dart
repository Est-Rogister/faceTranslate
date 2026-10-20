import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/live_translate_service.dart';

enum _ConversationStatus {
  waiting,
  recording,
  canceling,
  recognizing,
  translating,
  playing,
  warning,
  error,
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.languageA,
    required this.languageB,
    required this.messagesA,
    required this.messagesB,
    required this.onLanguagesChanged,
    required this.onEditLanguages,
    required this.onMessage,
    required this.onClearMessages,
    this.translationClientFactory,
    this.audioPlayerFactory,
    super.key,
  });

  final LanguageOption languageA;
  final LanguageOption languageB;
  final List<TranscriptMessage> messagesA;
  final List<TranscriptMessage> messagesB;
  final void Function(LanguageOption languageA, LanguageOption languageB)
  onLanguagesChanged;
  final VoidCallback onEditLanguages;
  final void Function(PartySide target, TranscriptMessage message) onMessage;
  final VoidCallback onClearMessages;
  final TranslationClientFactory? translationClientFactory;
  final TranslationAudioPlayerFactory? audioPlayerFactory;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with SingleTickerProviderStateMixin {
  static const _centerConsoleHeight = 54.0;
  static const _minimumPanelHeight = 108.0;
  static const _compactPanelThreshold = 240.0;

  late LanguageOption _languageA = widget.languageA;
  late LanguageOption _languageB = widget.languageB;
  late final AnimationController _motionController;
  late final TranslationAudioPlayer _audioPlayer;
  final ScrollController _feedAController = ScrollController();
  final ScrollController _feedBController = ScrollController();

  _ConversationStatus _status = _ConversationStatus.waiting;
  String _statusText = '等待说话';
  PartySide? _recordingSide;
  PartySide? _conflictSide;
  int? _activePointer;
  double? _pointerStartY;
  bool _cancelArmed = false;
  bool _busy = false;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordTimer;
  Timer? _limitTimer;
  Timer? _warningTimer;
  final Map<PartySide, TranslationClient> _translationClients = {};
  TranslationClient? _translationClient;
  PartySide? _liveTargetSide;
  String _liveSourceText = '';
  String _liveTranslationText = '';
  double _panelAFraction = 0.5;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    _audioPlayer =
        widget.audioPlayerFactory?.call() ?? QwenTranslationAudioPlayer();
  }

  @override
  void didUpdateWidget(covariant ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _languageA = widget.languageA;
    _languageB = widget.languageB;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _limitTimer?.cancel();
    _warningTimer?.cancel();
    unawaited(_disposeTranslationClients());
    unawaited(_audioPlayer.dispose());
    _motionController.dispose();
    _feedAController.dispose();
    _feedBController.dispose();
    super.dispose();
  }

  LanguageOption _languageFor(PartySide side) =>
      side == PartySide.a ? _languageA : _languageB;

  List<TranscriptMessage> _messagesFor(PartySide side) =>
      side == PartySide.a ? widget.messagesA : widget.messagesB;

  bool get _microphonesDisabled =>
      _busy && _status != _ConversationStatus.playing;

  void _setLanguages(LanguageOption languageA, LanguageOption languageB) {
    if (_busy || _recordingSide != null) return;
    unawaited(_disposeTranslationClients());
    setState(() {
      _languageA = languageA;
      _languageB = languageB;
      _setWaiting();
    });
    widget.onLanguagesChanged(languageA, languageB);
  }

  void _selectLanguage(PartySide side, LanguageOption language) {
    if (language.code == _languageFor(side).code) return;
    if (language.code == _languageFor(side.other).code) {
      _swapLanguages();
      return;
    }
    if (side == PartySide.a) {
      _setLanguages(language, _languageB);
    } else {
      _setLanguages(_languageA, language);
    }
  }

  void _swapLanguages() {
    if (_busy || _recordingSide != null) return;
    _setLanguages(_languageB, _languageA);
    _showToast('双方语言已交换');
  }

  void _editLanguages() {
    if (_busy || _recordingSide != null) {
      _showToast('请等待当前语音处理完成');
      return;
    }
    widget.onEditLanguages();
  }

  void _clearMessages() {
    _finishPlayback();
    widget.onClearMessages();
    _showToast('双方字幕已清空');
  }

  void _beginRecording(PartySide side, PointerDownEvent event) {
    if (_recordingSide != null) {
      if (_recordingSide != side) setState(() => _conflictSide = side);
      return;
    }
    if (_busy && _status != _ConversationStatus.playing) return;
    if (_status == _ConversationStatus.playing) _finishPlayback();

    final client = _translationClients.putIfAbsent(
      side,
      () =>
          widget.translationClientFactory?.call() ?? QwenLiveTranslateClient(),
    );
    if (!client.isConfigured) {
      _translationClients.remove(side);
      unawaited(client.dispose());
      setState(() {
        _status = _ConversationStatus.error;
        _statusText = '翻译服务未配置';
      });
      _showToast('请配置阿里云 API Key 和 Workspace ID');
      _returnToWaiting();
      return;
    }

    _recordTimer?.cancel();
    _limitTimer?.cancel();
    _warningTimer?.cancel();
    setState(() {
      _translationClient = client;
      _recordingSide = side;
      _conflictSide = null;
      _activePointer = event.pointer;
      _pointerStartY = event.position.dy;
      _cancelArmed = false;
      _recordingElapsed = Duration.zero;
      _liveTargetSide = side.other;
      _liveSourceText = '';
      _liveTranslationText = '';
      _status = _ConversationStatus.recording;
      _statusText = '正在录音 00:00';
    });
    unawaited(_startTranslation(client, side));

    _recordTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _recordingSide == null) return;
      _recordingElapsed += const Duration(milliseconds: 120);
      if (_cancelArmed) return;
      final seconds = _recordingElapsed.inSeconds.clamp(0, 60);
      setState(() {
        _statusText = '正在录音 00:${seconds.toString().padLeft(2, '0')}';
      });
    });
    _limitTimer = Timer(const Duration(seconds: 60), () {
      if (_recordingSide == side) _finishRecording(side, reachedLimit: true);
    });
  }

  Future<void> _startTranslation(
    TranslationClient client,
    PartySide sourceSide,
  ) async {
    try {
      await client.start(
        targetLanguage: _languageFor(sourceSide.other).modelCode,
        onSourceText: (text) {
          if (!mounted || _translationClient != client) return;
          setState(() => _liveSourceText = text);
        },
        onTranslationText: (text) {
          if (!mounted || _translationClient != client) return;
          setState(() => _liveTranslationText = text);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(sourceSide.other);
          });
        },
      );
    } catch (error) {
      if (!mounted || _translationClient != client) return;
      _handleTranslationError(client, error);
    }
  }

  void _trackRecording(PartySide side, PointerMoveEvent event) {
    if (_recordingSide != side ||
        _activePointer != event.pointer ||
        _pointerStartY == null) {
      return;
    }
    final distance = side == PartySide.a
        ? event.position.dy - _pointerStartY!
        : _pointerStartY! - event.position.dy;
    if (!_cancelArmed && distance >= 64) {
      setState(() {
        _cancelArmed = true;
        _status = _ConversationStatus.canceling;
        _statusText = '松开取消录音';
      });
    } else if (_cancelArmed && distance <= 44) {
      setState(() {
        _cancelArmed = false;
        _status = _ConversationStatus.recording;
      });
    }
  }

  void _endRecording(PartySide side, PointerEvent event) {
    if (_recordingSide != side || _activePointer != event.pointer) return;
    if (_cancelArmed || event is PointerCancelEvent) {
      _cancelRecording(side);
    } else {
      _finishRecording(side);
    }
  }

  void _resetRecording() {
    _recordTimer?.cancel();
    _limitTimer?.cancel();
    _recordingSide = null;
    _conflictSide = null;
    _activePointer = null;
    _pointerStartY = null;
    _cancelArmed = false;
  }

  void _cancelRecording(PartySide side) {
    if (_recordingSide != side) return;
    final client = _translationClient;
    setState(() {
      _resetRecording();
      _clearLiveTranscript();
      _status = _ConversationStatus.warning;
      _statusText = '录音已取消，请重试';
    });
    if (client != null) {
      unawaited(_cancelTranslation(client));
    }
    _showToast(
      _languageFor(side).isChinese
          ? '录音已取消，请重新按住说话'
          : 'Recording canceled, please hold to try again',
    );
    _returnToWaiting();
  }

  void _finishRecording(PartySide side, {bool reachedLimit = false}) {
    if (_recordingSide != side) return;
    final elapsed = _recordingElapsed;
    final client = _translationClient;
    setState(_resetRecording);

    if (elapsed < const Duration(seconds: 1) && !reachedLimit) {
      if (client != null) {
        unawaited(_cancelTranslation(client));
      }
      setState(() {
        _clearLiveTranscript();
        _status = _ConversationStatus.warning;
        _statusText = '说话时间太短，请重试';
      });
      _showToast('至少按住 1 秒再松开');
      _returnToWaiting();
      return;
    }
    if (client == null) {
      _handleTranslationError(null, const LiveTranslateException('翻译会话未就绪'));
      return;
    }
    setState(() {
      _busy = true;
      _status = _ConversationStatus.recognizing;
      _statusText = '正在识别...';
    });
    unawaited(_completeTranslation(client, side));
  }

  Future<void> _completeTranslation(
    TranslationClient client,
    PartySide sourceSide,
  ) async {
    final targetSide = sourceSide.other;
    final sourceLanguage = _languageFor(sourceSide);
    final targetLanguage = _languageFor(targetSide);
    try {
      if (mounted && _translationClient == client) {
        setState(() {
          _status = _ConversationStatus.translating;
          _statusText = '正在翻译...';
        });
      }
      final result = await client.stop();
      if (!mounted || _translationClient != client) return;
      final sourceText = result.sourceText.isEmpty
          ? (sourceLanguage.isChinese ? '语音输入' : 'Voice input')
          : result.sourceText;
      widget.onMessage(
        targetSide,
        TranscriptMessage(
          source: sourceText,
          translation: result.translatedText,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
          createdAt: DateTime.now(),
        ),
      );
      setState(() {
        _translationClient = null;
        _clearLiveTranscript();
        _status = _ConversationStatus.playing;
        _statusText = '正在播放翻译语音';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(targetSide);
      });
      if (result.audioPcm.isNotEmpty) {
        await _audioPlayer.play(result.audioPcm);
      }
      if (mounted && _status == _ConversationStatus.playing) {
        _finishPlayback();
      }
    } catch (error) {
      if (mounted && _translationClient == client) {
        _handleTranslationError(client, error);
      }
    }
  }

  Future<void> _cancelTranslation(TranslationClient client) async {
    _translationClients.removeWhere((_, value) => identical(value, client));
    try {
      await client.cancel();
    } finally {
      await client.dispose();
      if (mounted && _translationClient == client) {
        setState(() => _translationClient = null);
      }
    }
  }

  void _handleTranslationError(TranslationClient? client, Object error) {
    if (client != null && _translationClient != client) return;
    if (_recordingSide != null) _resetRecording();
    setState(() {
      _busy = false;
      _clearLiveTranscript();
      _status = _ConversationStatus.error;
      _statusText = '翻译失败，请重试';
    });
    _showToast(error.toString());
    if (client != null) unawaited(_cancelTranslation(client));
    _returnToWaiting();
  }

  Future<void> _disposeTranslationClients() async {
    final clients = _translationClients.values.toSet().toList();
    _translationClients.clear();
    _translationClient = null;
    await Future.wait(clients.map((client) => client.dispose()));
  }

  void _clearLiveTranscript() {
    _liveTargetSide = null;
    _liveSourceText = '';
    _liveTranslationText = '';
  }

  TranscriptMessage? _liveMessageFor(PartySide side) {
    if (_liveTargetSide != side ||
        (_liveSourceText.isEmpty && _liveTranslationText.isEmpty)) {
      return null;
    }
    return TranscriptMessage(
      source: _liveSourceText.isEmpty ? '正在识别...' : _liveSourceText,
      translation: _liveTranslationText.isEmpty
          ? '正在翻译...'
          : _liveTranslationText,
      sourceLanguage: _languageFor(side.other),
      targetLanguage: _languageFor(side),
      createdAt: DateTime.now(),
    );
  }

  void _scrollToBottom(PartySide side) {
    final controller = side == PartySide.a
        ? _feedAController
        : _feedBController;
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _finishPlayback() {
    unawaited(_audioPlayer.stop());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _setWaiting();
    });
  }

  void _setWaiting() {
    _status = _ConversationStatus.waiting;
    _statusText = '等待说话';
  }

  void _returnToWaiting() {
    _warningTimer?.cancel();
    _warningTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || _busy || _recordingSide != null) return;
      setState(_setWaiting);
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.center)),
      );
  }

  String _localizedStatus(PartySide side) {
    if (_languageFor(side).isChinese) return _statusText;
    if (_statusText.startsWith('正在录音')) {
      return _statusText.replaceFirst('正在录音', 'Recording');
    }
    return switch (_statusText) {
      '等待说话' => 'Ready to talk',
      '正在识别...' => 'Recognizing...',
      '正在翻译...' => 'Translating...',
      '正在播放翻译语音' => 'Playing translation',
      '松开取消录音' => 'Release to cancel',
      '说话时间太短，请重试' => 'Too short, please try again',
      '录音已取消，请重试' => 'Recording canceled, please try again',
      '翻译失败，请重试' => 'Translation failed, please try again',
      '翻译服务未配置' => 'Translation service is not configured',
      _ => _statusText,
    };
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (_status) {
      _ConversationStatus.recording => scheme.error,
      _ConversationStatus.canceling => AppTone.warning(context),
      _ConversationStatus.recognizing ||
      _ConversationStatus.translating => scheme.primary,
      _ConversationStatus.playing => AppTone.success(context),
      _ConversationStatus.warning => AppTone.warning(context),
      _ConversationStatus.error => scheme.error,
      _ => scheme.onSurfaceVariant,
    };
  }

  void _resizePanels(double deltaY, double availableHeight) {
    if (availableHeight <= _minimumPanelHeight * 2) return;
    final currentHeight = availableHeight * _panelAFraction;
    final nextHeight = (currentHeight + deltaY).clamp(
      _minimumPanelHeight,
      availableHeight - _minimumPanelHeight,
    );
    setState(() => _panelAFraction = nextHeight / availableHeight);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = math.max(
              0.0,
              constraints.maxHeight - _centerConsoleHeight,
            );
            final minimumHeight = math.min(
              _minimumPanelHeight,
              availableHeight / 2,
            );
            final panelAHeight = (availableHeight * _panelAFraction)
                .clamp(minimumHeight, availableHeight - minimumHeight)
                .toDouble();
            final panelBHeight = availableHeight - panelAHeight;
            return Column(
              children: [
                SizedBox(
                  key: const ValueKey('party-panel-a'),
                  height: panelAHeight,
                  child: Transform.rotate(
                    angle: math.pi,
                    child: _PartyPanel(
                      side: PartySide.a,
                      compact: panelAHeight < _compactPanelThreshold,
                      language: _languageA,
                      messages: _messagesFor(PartySide.a),
                      liveMessage: _liveMessageFor(PartySide.a),
                      scrollController: _feedAController,
                      recording: _recordingSide == PartySide.a,
                      canceling: _recordingSide == PartySide.a && _cancelArmed,
                      conflicted: _conflictSide == PartySide.a,
                      disabled: _microphonesDisabled,
                      motion: _motionController,
                      statusText: _localizedStatus(PartySide.a),
                      status: _status,
                      statusColor: _statusColor(context),
                      onLanguageChanged: (language) =>
                          _selectLanguage(PartySide.a, language),
                      onPointerDown: (event) =>
                          _beginRecording(PartySide.a, event),
                      onPointerMove: (event) =>
                          _trackRecording(PartySide.a, event),
                      onPointerEnd: (event) =>
                          _endRecording(PartySide.a, event),
                    ),
                  ),
                ),
                _CenterConsole(
                  disabled: _busy || _recordingSide != null,
                  onDrag: (deltaY) => _resizePanels(deltaY, availableHeight),
                  onSwap: _swapLanguages,
                  onEdit: _editLanguages,
                  onClear: _clearMessages,
                ),
                SizedBox(
                  key: const ValueKey('party-panel-b'),
                  height: panelBHeight,
                  child: _PartyPanel(
                    side: PartySide.b,
                    compact: panelBHeight < _compactPanelThreshold,
                    language: _languageB,
                    messages: _messagesFor(PartySide.b),
                    liveMessage: _liveMessageFor(PartySide.b),
                    scrollController: _feedBController,
                    recording: _recordingSide == PartySide.b,
                    canceling: _recordingSide == PartySide.b && _cancelArmed,
                    conflicted: _conflictSide == PartySide.b,
                    disabled: _microphonesDisabled,
                    motion: _motionController,
                    statusText: _localizedStatus(PartySide.b),
                    status: _status,
                    statusColor: _statusColor(context),
                    onLanguageChanged: (language) =>
                        _selectLanguage(PartySide.b, language),
                    onPointerDown: (event) =>
                        _beginRecording(PartySide.b, event),
                    onPointerMove: (event) =>
                        _trackRecording(PartySide.b, event),
                    onPointerEnd: (event) => _endRecording(PartySide.b, event),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PartyPanel extends StatelessWidget {
  const _PartyPanel({
    required this.side,
    required this.compact,
    required this.language,
    required this.messages,
    required this.liveMessage,
    required this.scrollController,
    required this.recording,
    required this.canceling,
    required this.conflicted,
    required this.disabled,
    required this.motion,
    required this.statusText,
    required this.status,
    required this.statusColor,
    required this.onLanguageChanged,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerEnd,
  });

  final PartySide side;
  final bool compact;
  final LanguageOption language;
  final List<TranscriptMessage> messages;
  final TranscriptMessage? liveMessage;
  final ScrollController scrollController;
  final bool recording;
  final bool canceling;
  final bool conflicted;
  final bool disabled;
  final Animation<double> motion;
  final String statusText;
  final _ConversationStatus status;
  final Color statusColor;
  final ValueChanged<LanguageOption> onLanguageChanged;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final void Function(PointerEvent event) onPointerEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChinese = language.isChinese;
    final accent = side == PartySide.a
        ? theme.colorScheme.primary
        : AppTone.success(context);
    final microphone = _MicrophoneButton(
      key: ValueKey('microphone-${side.name}'),
      accent: accent,
      recording: recording,
      canceling: canceling,
      conflicted: conflicted,
      disabled: disabled,
      motion: motion,
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerEnd: onPointerEnd,
    );

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
            : const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: compact
            ? Center(child: microphone)
            : Column(
                children: [
                  Expanded(
                    key: ValueKey('party-feed-${side.name}'),
                    child: messages.isEmpty && liveMessage == null
                        ? _EmptyFeed(isChinese: isChinese)
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount:
                                messages.length + (liveMessage == null ? 0 : 1),
                            separatorBuilder: (_, _) => Divider(
                              height: 24,
                              color: theme.colorScheme.outline,
                            ),
                            itemBuilder: (context, index) {
                              if (index < messages.length) {
                                return _MessageCard(message: messages[index]);
                              }
                              return _MessageCard(
                                message: liveMessage!,
                                isLive: true,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  microphone,
                  const SizedBox(height: 5),
                  _CompactLanguageDropdown(
                    key: ValueKey('conversation-language-${side.name}'),
                    value: language,
                    enabled: !disabled,
                    onChanged: onLanguageChanged,
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 20,
                    child: _StatusLabel(
                      text: statusText,
                      status: status,
                      color: statusColor,
                      motion: motion,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CompactLanguageDropdown extends StatelessWidget {
  const _CompactLanguageDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final LanguageOption value;
  final bool enabled;
  final ValueChanged<LanguageOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 132,
      height: 36,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LanguageOption>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: LanguageOption.values
              .map(
                (language) => DropdownMenuItem(
                  value: language,
                  child: Text(
                    language.nativeName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (language) {
                  if (language != null) onChanged(language);
                }
              : null,
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.isChinese});

  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isChinese ? '等待对方说话' : 'Waiting for the other person',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.isLive = false});

  final TranscriptMessage message;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetIsChinese = message.targetLanguage.isChinese;
    final sourceName = targetIsChinese
        ? message.sourceLanguage.nativeName
        : message.sourceLanguage.englishName;
    final targetName = targetIsChinese
        ? message.targetLanguage.nativeName
        : message.targetLanguage.englishName;
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isLive
            ? AppTone.primarySoft(context).withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.source,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message.translation,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$sourceName → $targetName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '$hour:$minute',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MicrophoneButton extends StatelessWidget {
  const _MicrophoneButton({
    required this.accent,
    required this.recording,
    required this.canceling,
    required this.conflicted,
    required this.disabled,
    required this.motion,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerEnd,
    super.key,
  });

  final Color accent;
  final bool recording;
  final bool canceling;
  final bool conflicted;
  final bool disabled;
  final Animation<double> motion;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final void Function(PointerEvent event) onPointerEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = canceling || conflicted
        ? AppTone.warning(context)
        : recording
        ? theme.colorScheme.error
        : accent;

    return SizedBox(
      width: 84,
      height: 84,
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, child) {
          final waveScale = 0.88 + motion.value * 0.3;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (recording)
                Transform.scale(
                  scale: canceling ? 1 : waveScale,
                  child: Opacity(
                    opacity: canceling ? 0.48 : 0.7 * (1 - motion.value),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: buttonColor, width: 2),
                      ),
                    ),
                  ),
                ),
              Listener(
                onPointerDown: disabled ? null : onPointerDown,
                onPointerMove: disabled ? null : onPointerMove,
                onPointerUp: disabled ? null : onPointerEnd,
                onPointerCancel: disabled ? null : onPointerEnd,
                child: Semantics(
                  button: true,
                  label: '按住说话',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: disabled
                          ? buttonColor.withValues(alpha: 0.42)
                          : buttonColor,
                      boxShadow: disabled
                          ? null
                          : [
                              BoxShadow(
                                color: buttonColor.withValues(alpha: 0.26),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    child: recording
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              final phase =
                                  motion.value * math.pi * 2 + index * 1.1;
                              final height = canceling
                                  ? 7.0 + (index - 2).abs() * 2
                                  : 8.0 + math.sin(phase).abs() * 18;
                              return Container(
                                width: 3,
                                height: height,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              );
                            }),
                          )
                        : const Icon(
                            Icons.mic_none_rounded,
                            color: Colors.white,
                            size: 29,
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CenterConsole extends StatelessWidget {
  const _CenterConsole({
    required this.disabled,
    required this.onDrag,
    required this.onSwap,
    required this.onEdit,
    required this.onClear,
  });

  final bool disabled;
  final ValueChanged<double> onDrag;
  final VoidCallback onSwap;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          Tooltip(
            message: '拖动调整双方区域',
            child: GestureDetector(
              key: const ValueKey('conversation-divider-handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _ConsoleButton(
            tooltip: '交换语言',
            icon: Icons.swap_vert_rounded,
            onPressed: disabled ? null : onSwap,
          ),
          const SizedBox(width: 10),
          _ConsoleButton(
            tooltip: '返回语言设置',
            icon: Icons.close_rounded,
            foreground: theme.colorScheme.primary,
            onPressed: onEdit,
          ),
          const SizedBox(width: 10),
          _ConsoleButton(
            tooltip: '清空字幕',
            icon: Icons.delete_outline_rounded,
            foreground: theme.colorScheme.error,
            onPressed: onClear,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ConsoleButton extends StatelessWidget {
  const _ConsoleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foreground,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: foreground ?? Theme.of(context).colorScheme.onSurfaceVariant,
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({
    required this.text,
    required this.status,
    required this.color,
    required this.motion,
  });

  final String text;
  final _ConversationStatus status;
  final Color color;
  final Animation<double> motion;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: motion,
          builder: (context, child) {
            if (status == _ConversationStatus.playing) {
              return SizedBox(
                width: 16,
                height: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(3, (index) {
                    final height =
                        4 +
                        math
                                .sin(
                                  (motion.value + index * 0.23) * math.pi * 2,
                                )
                                .abs() *
                            7;
                    return Container(
                      width: 3,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              );
            }
            final pulsing =
                status == _ConversationStatus.recognizing ||
                status == _ConversationStatus.translating;
            return Transform.scale(
              scale: pulsing ? 0.8 + motion.value * 0.38 : 1,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

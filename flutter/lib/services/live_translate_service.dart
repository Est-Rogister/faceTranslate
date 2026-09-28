import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

import 'live_translate_settings.dart';

abstract interface class TranslationClient {
  bool get isConfigured;

  Future<void> start({
    required String targetLanguage,
    required TextUpdateCallback onSourceText,
    required TextUpdateCallback onTranslationText,
  });

  Future<LiveTranslation> stop();

  Future<void> cancel();

  Future<void> dispose();
}

typedef TextUpdateCallback = void Function(String value);
typedef TranslationClientFactory = TranslationClient Function();

abstract interface class TranslationAudioPlayer {
  Future<void> play(Uint8List pcmBytes);

  Future<void> stop();

  Future<void> dispose();
}

typedef TranslationAudioPlayerFactory = TranslationAudioPlayer Function();

class LiveTranslation {
  const LiveTranslation({
    required this.sourceText,
    required this.translatedText,
    required this.audioPcm,
  });

  final String sourceText;
  final String translatedText;
  final Uint8List audioPcm;
}

abstract final class LiveTranslateConfig {
  static String get apiKey => LiveTranslateSettings.instance.apiKey;
  static bool get isConfigured => LiveTranslateSettings.instance.isConfigured;
  static Uri? get endpoint => LiveTranslateSettings.instance.endpoint;
  static bool get voiceCloneEnabled =>
      LiveTranslateSettings.instance.voiceCloneEnabled;
}

Map<String, dynamic> buildLiveTranslateSessionUpdate({
  required String targetLanguage,
  required bool voiceCloneEnabled,
}) {
  final session = <String, dynamic>{
    'output_modalities': ['text', 'audio'],
    'translation': {'language': targetLanguage},
  };
  if (voiceCloneEnabled) {
    session.addAll({
      'voice': 'default',
      'enable_voice_clone': true,
      'voice_clone_options': {'frequency': 'once'},
    });
  }
  return {'type': 'session.update', 'session': session};
}

String? validateVoiceCloneSessionUpdate(Map<String, dynamic> event) {
  final session = event['session'];
  if (session is! Map<String, dynamic>) {
    return '自定义节点未返回完整会话配置';
  }
  if (session['enable_voice_clone'] != true) {
    return '自定义节点未启用音色复刻';
  }
  if (session['voice'] != 'default') {
    return '自定义节点未使用实时复刻音色';
  }
  final options = session['voice_clone_options'];
  if (options is! Map<String, dynamic> || options['frequency'] != 'once') {
    return '自定义节点未接受音色复刻方式';
  }
  return null;
}

class LiveTranslateException implements Exception {
  const LiveTranslateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QwenLiveTranslateClient implements TranslationClient {
  QwenLiveTranslateClient({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _responseSettleTimer;
  Future<void>? _connectOperation;
  Future<void>? _recordingStartOperation;
  Completer<void>? _sessionCreated;
  Completer<void>? _sessionUpdated;
  Completer<void>? _sessionFinished;
  Completer<LiveTranslation>? _turnResult;
  TextUpdateCallback? _onSourceText;
  TextUpdateCallback? _onTranslationText;
  BytesBuilder _audioOutput = BytesBuilder(copy: false);
  String _sourceText = '';
  String _translatedText = '';
  String? _targetLanguage;
  bool _voiceCloneEnabled = false;
  bool _isRecording = false;
  bool _responseReady = false;
  bool _finishSent = false;
  bool _disposed = false;

  @override
  bool get isConfigured => LiveTranslateConfig.isConfigured;

  @override
  Future<void> start({
    required String targetLanguage,
    required TextUpdateCallback onSourceText,
    required TextUpdateCallback onTranslationText,
  }) {
    if (_disposed) {
      return Future.error(const LiveTranslateException('翻译会话已经关闭'));
    }
    if (_recordingStartOperation != null || _turnResult != null) {
      return Future.error(const LiveTranslateException('当前翻译会话已经开始'));
    }
    _turnResult = Completer<LiveTranslation>();
    _onSourceText = onSourceText;
    _onTranslationText = onTranslationText;
    _sourceText = '';
    _translatedText = '';
    _audioOutput = BytesBuilder(copy: false);
    _responseReady = false;
    _responseSettleTimer?.cancel();
    _recordingStartOperation = _startTurn(targetLanguage: targetLanguage);
    return _recordingStartOperation!;
  }

  Future<void> _startTurn({required String targetLanguage}) async {
    if (!isConfigured) {
      throw const LiveTranslateException('缺少阿里云 API Key 或 Workspace ID');
    }

    try {
      await _ensureConnected(targetLanguage);
      if (!await _recorder.hasPermission()) {
        throw const LiveTranslateException('麦克风权限未授权');
      }
      final audioStream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          streamBufferSize: 3200,
          autoGain: !_voiceCloneEnabled,
          echoCancel: !_voiceCloneEnabled,
          noiseSuppress: !_voiceCloneEnabled,
        ),
      );
      _isRecording = true;
      _audioSubscription = audioStream.listen((chunk) {
        if (chunk.isEmpty || _finishSent) return;
        _send({
          'type': 'input_audio_buffer.append',
          'audio': base64Encode(chunk),
        });
      }, onError: _handleSocketError);
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _ensureConnected(String targetLanguage) async {
    if (_socket?.readyState == WebSocket.open) {
      if (_targetLanguage != targetLanguage) {
        throw const LiveTranslateException('语言已变化，请重新建立翻译会话');
      }
      return;
    }
    final activeConnection = _connectOperation;
    if (activeConnection != null) {
      await activeConnection;
      return;
    }
    final operation = _connect(targetLanguage);
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      _connectOperation = null;
    }
  }

  Future<void> _connect(String targetLanguage) async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _socket = null;
    _sessionCreated = Completer<void>();
    _sessionUpdated = Completer<void>();
    _sessionFinished = Completer<void>();
    _targetLanguage = targetLanguage;
    _voiceCloneEnabled = LiveTranslateConfig.voiceCloneEnabled;
    _finishSent = false;

    _socket = await WebSocket.connect(
      LiveTranslateConfig.endpoint!.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${LiveTranslateConfig.apiKey}',
      },
      compression: CompressionOptions.compressionOff,
    ).timeout(const Duration(seconds: 15));
    _socketSubscription = _socket!.listen(
      _handleServerMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
      cancelOnError: false,
    );

    await _sessionCreated!.future.timeout(const Duration(seconds: 15));
    _send(
      buildLiveTranslateSessionUpdate(
        targetLanguage: targetLanguage,
        voiceCloneEnabled: _voiceCloneEnabled,
      ),
    );
    await _sessionUpdated!.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<LiveTranslation> stop() async {
    final operation = _recordingStartOperation;
    final result = _turnResult;
    if (operation == null || result == null) {
      throw const LiveTranslateException('翻译会话尚未开始');
    }
    try {
      await operation;
      await _stopRecorder();
      _isRecording = false;
      if (_responseReady) {
        _completeTurnResult();
      } else {
        await _sendTrailingSilence();
        _scheduleTurnCompletion();
      }
      return await result.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw const LiveTranslateException('翻译响应超时'),
      );
    } finally {
      _recordingStartOperation = null;
      _turnResult = null;
      _onSourceText = null;
      _onTranslationText = null;
      _responseReady = false;
      _responseSettleTimer?.cancel();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _recordingStartOperation;
      await _stopRecorder();
      _isRecording = false;
      if (_socket?.readyState == WebSocket.open) {
        _send({'type': 'input_audio_buffer.clear'});
      }
    } catch (_) {
      await _stopRecorder();
    } finally {
      _recordingStartOperation = null;
      _turnResult = null;
      _onSourceText = null;
      _onTranslationText = null;
      _responseReady = false;
      _responseSettleTimer?.cancel();
    }
  }

  void _handleServerMessage(dynamic rawMessage) {
    try {
      final text = rawMessage is String
          ? rawMessage
          : utf8.decode(rawMessage as List<int>);
      final event = jsonDecode(text) as Map<String, dynamic>;
      final type = event['type'] as String?;
      switch (type) {
        case 'session.created':
          _complete(_sessionCreated);
        case 'session.updated':
          if (_voiceCloneEnabled) {
            final validationError = validateVoiceCloneSessionUpdate(event);
            if (validationError != null) {
              _fail(LiveTranslateException(validationError));
              return;
            }
          }
          _complete(_sessionUpdated);
        case 'conversation.item.input_audio_transcription.delta':
          _responseReady = false;
          _sourceText += event['delta'] as String? ?? '';
          _onSourceText?.call(_sourceText);
        case 'conversation.item.input_audio_transcription.completed':
          final transcript = event['transcript'] as String?;
          if (transcript != null && transcript.isNotEmpty) {
            _sourceText = transcript;
            _onSourceText?.call(_sourceText);
          }
        case 'response.text.delta':
        case 'response.audio_transcript.delta':
          _translatedText += event['delta'] as String? ?? '';
          _onTranslationText?.call(_translatedText);
          _scheduleTurnCompletion();
        case 'response.text.done':
          _setFinalTranslation(event['text']);
        case 'response.audio_transcript.done':
          _setFinalTranslation(event['transcript']);
        case 'response.audio.delta':
          final delta = event['delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            _audioOutput.add(base64Decode(delta));
            _scheduleTurnCompletion();
          }
        case 'response.done':
          _readResponseFallback(event['response']);
          _responseReady = true;
          if (!_isRecording) _completeTurnResult();
        case 'session.finished':
          _complete(_sessionFinished);
        case 'error':
        case 'conversation.item.input_audio_transcription.failed':
          final error = event['error'];
          final message = error is Map
              ? error['message']?.toString()
              : event['message']?.toString();
          _fail(LiveTranslateException(message ?? '阿里云实时翻译请求失败'));
      }
    } catch (error, stackTrace) {
      _fail(const LiveTranslateException('无法解析实时翻译响应'), stackTrace);
    }
  }

  void _setFinalTranslation(dynamic text) {
    if (text is String && text.isNotEmpty) {
      _translatedText = text;
      _onTranslationText?.call(_translatedText);
      _scheduleTurnCompletion();
    }
  }

  void _readResponseFallback(dynamic response) {
    if (_translatedText.isNotEmpty || response is! Map) return;
    final output = response['output'];
    if (output is! List) return;
    for (final item in output) {
      if (item is! Map || item['content'] is! List) continue;
      for (final content in item['content'] as List) {
        if (content is! Map) continue;
        final text = content['transcript'] ?? content['text'];
        if (text is String && text.isNotEmpty) {
          _translatedText = text;
          _onTranslationText?.call(_translatedText);
          _scheduleTurnCompletion();
          return;
        }
      }
    }
  }

  void _completeTurnResult() {
    final result = _turnResult;
    if (result == null || result.isCompleted) return;
    if (_translatedText.trim().isEmpty) {
      result.completeError(const LiveTranslateException('未收到翻译结果，请重试'));
    } else {
      result.complete(
        LiveTranslation(
          sourceText: _sourceText.trim(),
          translatedText: _translatedText.trim(),
          audioPcm: _audioOutput.takeBytes(),
        ),
      );
    }
  }

  void _scheduleTurnCompletion() {
    if (_isRecording || _translatedText.trim().isEmpty) return;
    _responseSettleTimer?.cancel();
    _responseSettleTimer = Timer(const Duration(milliseconds: 900), () {
      _completeTurnResult();
    });
  }

  void _handleSocketError(Object error, [StackTrace? stackTrace]) {
    _fail(LiveTranslateException('实时翻译连接失败：$error'), stackTrace);
  }

  void _handleSocketDone() {
    _socket = null;
    if (!_disposed && _turnResult != null && !_turnResult!.isCompleted) {
      _fail(const LiveTranslateException('实时翻译连接已断开'));
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    _completeError(_sessionCreated, error, stackTrace);
    _completeError(_sessionUpdated, error, stackTrace);
    _completeError(_turnResult, error, stackTrace);
  }

  void _send(Map<String, dynamic> event) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw const LiveTranslateException('实时翻译连接不可用');
    }
    socket.add(jsonEncode(event));
  }

  Future<void> _stopRecorder() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> _sendTrailingSilence() async {
    final silence = base64Encode(Uint8List(3200));
    for (var chunk = 0; chunk < 10; chunk++) {
      if (_turnResult?.isCompleted ?? true) return;
      _send({'type': 'input_audio_buffer.append', 'audio': silence});
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _closeSocket() async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null && socket.readyState == WebSocket.open) {
      await socket.close(WebSocketStatus.normalClosure);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _responseSettleTimer?.cancel();
    await _stopRecorder();
    _isRecording = false;
    if (_socket?.readyState == WebSocket.open && !_finishSent) {
      _finishSent = true;
      _send({'type': 'session.finish'});
      try {
        await _sessionFinished?.future.timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _closeSocket();
    await _recorder.dispose();
  }

  static void _complete<T>(Completer<T>? completer, [T? value]) {
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
  }

  static void _completeError<T>(
    Completer<T>? completer,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}

class QwenTranslationAudioPlayer implements TranslationAudioPlayer {
  QwenTranslationAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    final bytes = _hasWaveHeader(pcmBytes)
        ? pcmBytes
        : _wrapPcmAsWave(pcmBytes, sampleRate: 24000, channels: 1);
    final completed = Completer<void>();
    late final StreamSubscription<void> subscription;
    subscription = _player.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    try {
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      await completed.future.timeout(const Duration(minutes: 2));
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();

  static bool _hasWaveHeader(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46;

  static Uint8List _wrapPcmAsWave(
    Uint8List pcmBytes, {
    required int sampleRate,
    required int channels,
  }) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final output = Uint8List(44 + pcmBytes.length);
    final data = ByteData.sublistView(output);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        output[offset + index] = value.codeUnitAt(index);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + pcmBytes.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, pcmBytes.length, Endian.little);
    output.setRange(44, output.length, pcmBytes);
    return output;
  }
}
